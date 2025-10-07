use std::{
    collections::HashMap,
    ops::{Deref, DerefMut},
};

use crate::{
    ast,
    diagnostic::{Diagnostic, Span},
    ir::{
        BinOp, Body, BodyId, Expr, ExprKind, Generic, Local, ModuleId, Pattern, PatternKind, Type,
    },
    lower::{Lowerer, r#type::TypeLowerer},
    parse::Token,
};

pub struct BodyLowerer<'a, 'b> {
    lowerer:   &'a mut Lowerer<'b>,
    module_id: ModuleId,
    body_id:   BodyId,
    scope:     Vec<usize>,
}

impl<'a, 'b> BodyLowerer<'a, 'b> {
    pub fn new(lowerer: &'a mut Lowerer<'b>, module_id: ModuleId, body_id: BodyId) -> Self {
        Self {
            lowerer,
            module_id,
            body_id,
            scope: Vec::new(),
        }
    }

    pub fn body(&self) -> &Body {
        &self.lowerer.unit[self.body_id]
    }

    pub fn body_mut(&mut self) -> &mut Body {
        &mut self.lowerer.unit[self.body_id]
    }

    pub fn lower_type(&mut self, ast: &ast::Node) -> Type {
        let generics = self.body().generics.clone();
        let module_id = self.module_id;
        TypeLowerer::new(self, &generics, module_id).lower_type(ast)
    }

    pub fn lower_pattern(&mut self, ast: &ast::Node, ty: &Type) -> Pattern {
        match ast.kind {
            ast::Kind::BindingPattern => {
                let name = ast.string(0).unwrap();

                let local = Local {
                    name: Some(name.into()),
                    ty:   ty.clone(),
                };

                let local_index = self.body().locals.len();
                self.body_mut().locals.push(local);

                self.scope.push(local_index);

                let kind = PatternKind::Binding(local_index);
                let span = ast.span;

                Pattern { kind, span }
            }

            ast::Kind::Error => Pattern {
                kind: PatternKind::Wildcard,
                span: ast.span,
            },

            _ => unreachable!("{:?}", ast.kind),
        }
    }

    pub fn scope<T>(&mut self, mut f: impl FnMut(&mut BodyLowerer<'_, '_>) -> T) -> T {
        // save scope
        let scope_len = self.scope.len();

        let output = f(self);

        // restore scope
        self.scope.truncate(scope_len);

        output
    }

    pub fn lower_expr(&mut self, ast: &ast::Node, ty: &Type) -> Expr {
        let mut expr = match ast.kind {
            ast::Kind::IntExpr => self.lower_int_expr(ast, ty),
            ast::Kind::TrueExpr => self.lower_true_expr(ast, ty),
            ast::Kind::FalseExpr => self.lower_false_expr(ast, ty),
            ast::Kind::LetExpr => self.lower_let_expr(ast, ty),
            ast::Kind::PathExpr => self.lower_path_expr(ast, ty),
            ast::Kind::CallExpr => self.lower_call_expr(ast, ty),
            ast::Kind::BinaryExpr => self.lower_binary_expr(ast, ty),
            ast::Kind::BlockExpr => self.lower_block_expr(ast, ty),

            ast::Kind::Error => Expr::error(ast.span),

            _ => unreachable!("{:?}", ast.kind),
        };

        // we ensure that the actual type is a subtype of the expected type
        // if this is not the case, we set the type to `Type::Error` to prevent
        // duplicate diagnostics
        if !self.check_type(&expr.ty, ty, expr.span) {
            expr.ty = Type::Error;
        }

        expr
    }

    pub fn check_type(&mut self, sub_type: &Type, super_type: &Type, span: Span) -> bool {
        if !self.unit.is_subtype_of(sub_type, super_type) {
            let diagnostic = Diagnostic::error(format!(
                "expected type `{super_type:?}` but found `{sub_type:?}`"
            ))
            .label(span, "here");

            self.error(diagnostic);

            return false;
        }

        true
    }

    fn lower_int_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let value = ast.string(0).unwrap();
        let value = value.parse::<i64>().unwrap();

        let kind = ExprKind::Int(value);

        let ty = match value >= 0 {
            true => Type::Nat,
            false => Type::Int,
        };

        let span = ast.span;

        Expr { kind, ty, span }
    }

    fn lower_true_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let kind = ExprKind::Bool(true);
        let ty = Type::Bool;
        let span = ast.span;

        Expr { kind, ty, span }
    }

    fn lower_false_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let kind = ExprKind::Bool(false);
        let ty = Type::Bool;
        let span = ast.span;

        Expr { kind, ty, span }
    }

    fn lower_let_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let value = match ast.semantic_children().count() {
            4 => self.lower_expr(ast.node(3), &Type::Unknown),

            6 => {
                let ty = self.lower_type(ast.node(3));
                self.lower_expr(ast.node(5), &ty)
            }

            _ => unreachable!(),
        };

        let pattern = self.lower_pattern(ast.node(1), &value.ty);

        if pattern.is_refutable() {
            let diagnostic = Diagnostic::error("pattern in let expression is refutable")
                .label(ast.span, "found here");

            self.error(diagnostic);
        }

        let kind = ExprKind::Let(pattern, Box::new(value));
        let ty = Type::None;
        let span = ast.span;

        Expr { kind, ty, span }
    }

    fn lower_path_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let segments = ast
            .node(0)
            .children
            .iter()
            .filter_map(|c| match c {
                ast::Child::Token(Token::Ident, s) => Some(s),
                _ => None,
            })
            .collect::<Vec<_>>();

        if segments.len() == 1 {
            for &local_index in self.scope.iter().rev() {
                let local = &self.body().locals[local_index];

                if local.name.as_ref() != Some(segments[0]) {
                    continue;
                }

                let kind = ExprKind::Local(local_index);
                let ty = local.ty.clone();
                let span = ast.span;

                return Expr { kind, ty, span };
            }
        }

        let mut curr = self.module_id;

        for segment in &segments[..segments.len() - 1] {
            let Some(module_id) = self.unit[curr].modules.get(*segment) else {
                let diagnostic = Diagnostic::error(format!("module `{segment}` not found"))
                    .label(ast.span, "in path found here");

                self.error(diagnostic);

                return Expr::error(ast.span);
            };

            curr = *module_id;
        }

        let name = segments.last().unwrap();

        if let Some(&body) = self.unit[curr].bodies.get(*name) {
            let ty = Type::Body {
                body_id:  body,
                generics: Vec::new(),
            };

            let kind = ExprKind::Body(body);
            let span = ast.span;

            return Expr { kind, ty, span };
        }

        let diagnostic = Diagnostic::error(format!("item `{name}` not found"))
            .label(ast.span, "in path found here");

        self.error(diagnostic);

        Expr::error(ast.span)
    }

    fn lower_call_expr(&mut self, ast: &ast::Node, ty: &Type) -> Expr {
        let callee = self.lower_expr(ast.node(0), &Type::Unknown);
        let args = ast.nodes().skip(1).collect::<Vec<_>>();

        match callee.ty {
            Type::Body { body_id, .. } => {
                // ensure correct argument count
                if args.len() != self.unit[body_id].params.len() {
                    let diagnostic = Diagnostic::error(format!(
                        "wrong number of arguments, expected `{}` found `{}",
                        self.unit[body_id].params.len(),
                        args.len(),
                    ))
                    .label(ast.span, "in expression found here");

                    self.error(diagnostic);

                    return Expr::error(ast.span);
                }

                // create the generics map
                let mut map = HashMap::new();

                // unify the output with the expected type
                let body_ty = self.unit[body_id].ty.clone();
                self.unify_types(&body_ty, ty, &mut map, ast.span, false);

                let mut exprs = Vec::new();

                // for each argument, instantiate the expected type with the map
                // and lower the expression, then unify that type with the actual type
                for (param, arg) in self.unit[body_id].params.clone().into_iter().zip(args) {
                    let mut instance = param.ty.clone();
                    Self::instantiate_type(&mut instance, &map);
                    self.unit.normalize_type(&mut instance);
                    let expr = self.lower_expr(arg, &instance);

                    self.unify_types(&expr.ty, &param.ty, &mut map, ast.span, true);
                    exprs.push(expr);
                }

                let body = &self.unit[body_id];

                let mut ty = body.ty.clone();
                Self::instantiate_type(&mut ty, &map);
                self.unit.normalize_type(&mut ty);

                let mut generics = Vec::new();

                for param in body.generics.clone() {
                    let ty = map.remove(&param.generic).unwrap_or(Type::Unknown);

                    if let Type::Unknown = ty {
                        let diagnostic = Diagnostic::error("generic type not specialized")
                            .label(ast.span, "in expression found here");

                        self.error(diagnostic);
                    }

                    generics.push(ty);
                }

                let kind = ExprKind::CallBody(body_id, generics, exprs);
                let span = ast.span;

                Expr { kind, ty, span }
            }

            ty => {
                let diagnostic = Diagnostic::error(format!("type `{ty:?}` is not callable"))
                    .label(ast.span, "in expression found here");

                self.error(diagnostic);

                Expr::error(ast.span)
            }
        }
    }

    fn unify_types(
        &mut self,
        lhs: &Type,
        rhs: &Type,
        map: &mut HashMap<Generic, Type>,
        span: Span,
        is_input: bool,
    ) {
        match (lhs, rhs) {
            (lhs, Type::Generic { generic }) if is_input => {
                if map.get(generic).is_none_or(|t| !t.is_known()) {
                    map.insert(*generic, lhs.clone());
                }

                if let Some(rhs) = map.get(generic) {
                    self.check_type(lhs, rhs, span);
                }
            }

            (Type::Generic { generic }, rhs) if !map.contains_key(generic) && !is_input => {
                map.insert(*generic, rhs.clone());
            }

            (Type::Union { variants: lhs }, Type::Union { variants: rhs }) => {
                let mut lhs = lhs.clone();
                let mut rhs = rhs.clone();

                lhs.retain(|lhs| {
                    let len = rhs.len();
                    rhs.retain(|rhs| !self.unit.is_subtype_of(lhs, rhs));
                    rhs.len() == len
                });

                let mut rhs = Type::Union { variants: rhs };
                self.unit.normalize_type(&mut rhs);

                for lhs in lhs {
                    self.unify_types(&lhs, &rhs, map, span, is_input);
                }
            }

            (Type::Union { variants }, rhs) => {
                for lhs in variants {
                    self.unify_types(lhs, rhs, map, span, is_input);
                }
            }

            (lhs, Type::Union { variants }) => {
                for rhs in variants {
                    self.unify_types(lhs, rhs, map, span, is_input);
                }
            }

            (_, _) => {}
        }
    }

    fn instantiate_type(ty: &mut Type, map: &HashMap<Generic, Type>) {
        match ty {
            Type::Nat
            | Type::Int
            | Type::Num
            | Type::Str
            | Type::Bool
            | Type::None
            | Type::Never
            | Type::Unknown
            | Type::Error => {}

            Type::Body { generics, .. } => {
                for generic in generics {
                    Self::instantiate_type(generic, map);
                }
            }

            Type::Record { fields } => {
                for field in fields {
                    Self::instantiate_type(&mut field.ty, map);
                }
            }

            Type::Union { variants } => {
                for variant in variants {
                    Self::instantiate_type(variant, map);
                }
            }

            Type::Generic { generic } => match map.get(generic) {
                Some(s) => *ty = s.clone(),
                None => *ty = Type::Unknown,
            },
        }
    }

    fn lower_binary_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let op = match ast.token(1).unwrap() {
            Token::Plus => BinOp::Add,
            Token::Minus => BinOp::Sub,
            Token::Star => BinOp::Mul,
            Token::Slash => BinOp::Div,
            Token::Percent => BinOp::Mod,

            _ => unreachable!(),
        };

        let lhs = self.lower_expr(ast.node(0), &Type::Unknown);
        let rhs = self.lower_expr(ast.node(2), &Type::Unknown);

        use Type::{Error, Int, Nat, Num};

        let ty = match op {
            BinOp::Add => match (&lhs.ty, &rhs.ty) {
                (Nat, Nat) => Nat,
                (Int | Nat, Int | Nat) => Int,
                (Int | Nat | Num, Int | Nat | Num) => Num,

                (_, _) => Error,
            },

            BinOp::Sub => match (&lhs.ty, &rhs.ty) {
                (Nat | Int, Nat | Int) => Int,
                (Nat | Int | Num, Nat | Int | Num) => Int,

                (_, _) => Error,
            },

            BinOp::Mul => match (&lhs.ty, &rhs.ty) {
                (Nat, Nat) => Nat,
                (Nat | Int, Nat | Int) => Int,
                (Nat | Int | Num, Nat | Int | Num) => Num,

                (_, _) => Error,
            },

            BinOp::Div => match (&lhs.ty, &rhs.ty) {
                (Nat | Int | Num, Nat | Int | Num) => Num,

                (_, _) => Error,
            },

            BinOp::Mod => match (&lhs.ty, &rhs.ty) {
                (Nat, Nat) => Nat,
                (Nat | Int, Nat | Int) => Int,
                (Nat | Int | Num, Nat | Int | Num) => Num,

                (_, _) => Error,
            },
        };

        if let Error = ty {
            let diagnostic = Diagnostic::error(format!(
                "operator `{op}` is not implemented for `{lhs:?}` and `{rhs:?}`",
                lhs = lhs.ty,
                rhs = rhs.ty,
            ))
            .label(ast.span, "in expression here");

            self.error(diagnostic);
        }

        let kind = ExprKind::Binary(op, Box::new(lhs), Box::new(rhs));
        let span = ast.span;

        Expr { kind, ty, span }
    }

    fn lower_block_expr(&mut self, ast: &ast::Node, ty: &Type) -> Expr {
        let mut exprs = Vec::new();

        self.scope(|lowerer| {
            let count = ast.nodes().count();

            for (i, node) in ast.nodes().enumerate() {
                let is_last = i == count - 1;
                let ty = if is_last { ty } else { &Type::Unknown };
                let expr = lowerer.lower_expr(node, ty);
                exprs.push(expr);
            }
        });

        let ty = match exprs.last() {
            Some(expr) => expr.ty.clone(),
            None => Type::None,
        };

        let kind = ExprKind::Block(exprs);
        let span = ast.span;
        Expr { kind, ty, span }
    }
}

impl<'a> Deref for BodyLowerer<'_, 'a> {
    type Target = Lowerer<'a>;

    fn deref(&self) -> &Self::Target {
        self.lowerer
    }
}

impl DerefMut for BodyLowerer<'_, '_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.lowerer
    }
}
