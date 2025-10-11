use std::{
    collections::HashMap,
    ops::{Deref, DerefMut},
};

use crate::{
    ast,
    diagnostic::{Diagnostic, Span},
    ir::{
        BinOp, Body, BodyId, Expr, ExprField, ExprKind, Generic, Local, ModuleId, Pattern,
        PatternKind, Type, TypeField,
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

    pub fn find_module(&mut self, segments: &[impl AsRef<str>], span: Span) -> Option<ModuleId> {
        let module_id = self.module_id;
        match self.unit.find_module(module_id, segments) {
            Ok(module_id) => Some(module_id),
            Err(segment) => {
                let diagnostic = Diagnostic::error(format!(
                    "module `{segment}` not found",
                    segment = segment.as_ref(),
                ))
                .label(span, "in path found here");

                self.error(diagnostic);

                None
            }
        }
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

    pub fn coerce_expr(&mut self, expr: Expr, from: &Type, to: &Type) -> Expr {
        if self.unit.is_subtype_of(from, to) {
            return expr;
        }

        let mut from = from.clone();
        let mut to = to.clone();

        self.unit.normalize_type(&mut from);
        self.unit.normalize_type(&mut to);

        match (&from, &to) {
            (Type::Union(from_variants), Type::Union(to_variants))
                if from_variants.iter().all(|from| {
                    to_variants
                        .iter()
                        .any(|to| self.unit.is_subtype_of(from, to))
                }) =>
            {
                let span = expr.span;
                let kind = ExprKind::Union(Box::new(expr));
                let ty = to.clone();

                Expr { kind, ty, span }
            }

            (from, Type::Union(variants))
                if variants.iter().any(|to| self.unit.is_subtype_of(from, to)) =>
            {
                let span = expr.span;
                let kind = ExprKind::Union(Box::new(expr));
                let ty = to.clone();

                Expr { kind, ty, span }
            }

            (Type::Alias { alias_id, generics }, to) => {
                let from = self.unit.instantiate_alias(*alias_id, generics);
                self.coerce_expr(expr, &from, to)
            }

            (from, Type::Alias { alias_id, generics }) => {
                let to = self.unit.instantiate_alias(*alias_id, generics);
                self.coerce_expr(expr, from, &to)
            }

            (
                Type::Newtype {
                    newtype_id,
                    generics,
                },
                to,
            ) => {
                let from = self.unit.instantiate_newtype(*newtype_id, generics);

                let span = expr.span;
                let kind = ExprKind::Demote(*newtype_id, Box::new(expr));
                let ty = from.clone();

                let expr = Expr { kind, ty, span };
                self.coerce_expr(expr, &from, to)
            }

            (from, to) => {
                let diagnostic = Diagnostic::error(format!(
                    "type `{from}` not assignable to `{to}`",
                    from = self.unit.format_type(from),
                    to = self.unit.format_type(to),
                ))
                .label(expr.span, "here");

                self.error(diagnostic);

                Expr::error(expr.span)
            }
        }
    }

    pub fn lower_expr(&mut self, ast: &ast::Node, ty: &Type) -> Expr {
        let expr = match ast.kind {
            ast::Kind::IntExpr => self.lower_int_expr(ast, ty),
            ast::Kind::TrueExpr => self.lower_true_expr(ast, ty),
            ast::Kind::FalseExpr => self.lower_false_expr(ast, ty),
            ast::Kind::NoneExpr => self.lower_none_expr(ast, ty),
            ast::Kind::LetExpr => self.lower_let_expr(ast, ty),
            ast::Kind::PathExpr => self.lower_path_expr(ast, ty),
            ast::Kind::PromoteExpr => self.lower_promote_expr(ast, ty),
            ast::Kind::CallExpr => self.lower_call_expr(ast, ty),
            ast::Kind::BinaryExpr => self.lower_binary_expr(ast, ty),
            ast::Kind::RecordExpr => self.lower_record_expr(ast, ty),
            ast::Kind::BlockExpr => self.lower_block_expr(ast, ty),

            ast::Kind::Error => Expr::error(ast.span),

            _ => unreachable!("{:?}", ast.kind),
        };

        let from = expr.ty.clone();
        self.coerce_expr(expr, &from, ty)
    }

    fn lower_int_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let value = ast.string(0).unwrap();
        let value = value.parse::<i64>().unwrap();

        let kind = ExprKind::Num(value);

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

    fn lower_none_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let kind = ExprKind::None;
        let ty = Type::None;
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
        let segments = ast.node(0).idents().collect::<Vec<_>>();

        if segments.len() == 1 {
            for &local_index in self.scope.iter().rev() {
                let local = &self.body().locals[local_index];

                if local.name.as_deref() != Some(segments[0]) {
                    continue;
                }

                let kind = ExprKind::Local(local_index);
                let ty = local.ty.clone();
                let span = ast.span;

                return Expr { kind, ty, span };
            }
        }

        let Some(module_id) = self.find_module(&segments, ast.span) else {
            return Expr::error(ast.span);
        };

        let &name = segments.last().unwrap();

        if let Some(&body_id) = self.unit[module_id].bodies.get(name) {
            let ty = Type::Body {
                body_id,
                generics: Vec::new(),
            };

            let kind = ExprKind::Body(body_id);
            let span = ast.span;

            return Expr { kind, ty, span };
        }

        let diagnostic = Diagnostic::error(format!("item `{name}` not found"))
            .label(ast.span, "in path found here");

        self.error(diagnostic);

        Expr::error(ast.span)
    }

    fn lower_promote_expr(&mut self, ast: &ast::Node, ty: &Type) -> Expr {
        let segments = ast.node(0).idents().collect::<Vec<_>>();

        let Some(module_id) = self.find_module(&segments, ast.span) else {
            return Expr::error(ast.span);
        };

        let &name = segments.last().unwrap();

        let Some(&newtype_id) = self.unit[module_id].newtypes.get(name) else {
            let diagnostic = Diagnostic::error(format!("type `{name}` not found"))
                .label(ast.span, "in path found here");

            self.error(diagnostic);

            return Expr::error(ast.span);
        };

        let mut map = HashMap::new();

        let generics = self.unit[newtype_id]
            .generics
            .iter()
            .map(|p| Type::Generic(p.generic))
            .collect();

        let newtype_ty = Type::Newtype {
            newtype_id,
            generics,
        };

        self.unify_types(&newtype_ty, ty, &mut map, false);

        let mut ty = self.unit[newtype_id].ty.clone();
        ty.instantiate(&map);

        let value = self.lower_expr(ast.node(1), &ty);
        let newtype_ty = &self.unit[newtype_id].ty;
        self.unify_types(&value.ty, newtype_ty, &mut map, true);

        let mut generics = Vec::new();

        for param in self.unit[newtype_id].generics.clone() {
            let ty = map.remove(&param.generic).unwrap_or(Type::Unknown);

            if !ty.is_known() {
                let diagnostic = Diagnostic::error("generic type not specialized")
                    .label(ast.span, "in expression found here");

                self.error(diagnostic);
            }

            generics.push(ty);
        }

        let ty = Type::Newtype {
            newtype_id,
            generics,
        };

        let kind = ExprKind::Promote(newtype_id, Box::new(value));
        let span = ast.span;

        Expr { kind, ty, span }
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
                let body_ty = &self.unit[body_id].ty;
                self.unify_types(body_ty, ty, &mut map, false);

                let mut exprs = Vec::new();

                // for each argument, instantiate the expected type with the map
                // and lower the expression, then unify that type with the actual type
                for (param, arg) in self.unit[body_id].params.clone().into_iter().zip(args) {
                    let mut instance = param.ty.clone();
                    instance.instantiate(&map);
                    self.unit.normalize_type(&mut instance);
                    let expr = self.lower_expr(arg, &instance);

                    self.unify_types(&expr.ty, &param.ty, &mut map, true);
                    exprs.push(expr);
                }

                let body = &self.unit[body_id];

                let mut ty = body.ty.clone();
                ty.instantiate(&map);
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
                let diagnostic = Diagnostic::error(format!(
                    "type `{ty}` is not callable",
                    ty = self.unit.format_type(&ty),
                ))
                .label(ast.span, "in expression found here");

                self.error(diagnostic);

                Expr::error(ast.span)
            }
        }
    }

    /// Unify two types extracting the specializations for generics.
    fn unify_types(
        &self,
        sub_type: &Type,
        super_type: &Type,
        map: &mut HashMap<Generic, Type>,
        is_input: bool,
    ) {
        let mut sub_type = sub_type.clone();
        let mut super_type = super_type.clone();
        self.unit.normalize_type(&mut sub_type);
        self.unit.normalize_type(&mut super_type);

        match (&sub_type, &super_type) {
            (sub_type, Type::Generic(generic)) if is_input => {
                if map.get(generic).is_none_or(|t| !t.is_known()) {
                    map.insert(*generic, sub_type.clone());
                }
            }

            (Type::Generic(generic), super_type) if !is_input => {
                if let Some(sub_type) = map.get_mut(generic) {
                    *sub_type = Type::Unknown;
                } else {
                    map.insert(*generic, super_type.clone());
                }
            }

            (Type::Union(sub_variants), Type::Union(super_variants)) => {
                let mut sub_variants = sub_variants.clone();
                let mut super_variants = super_variants.clone();

                sub_variants.retain(|lhs| {
                    let len = super_variants.len();
                    super_variants.retain(|rhs| !self.unit.is_subtype_of(lhs, rhs));
                    super_variants.len() == len
                });

                let mut super_type = Type::Union(super_variants);
                self.unit.normalize_type(&mut super_type);

                for sub_variant in sub_variants {
                    self.unify_types(&sub_variant, &super_type, map, is_input);
                }
            }

            (Type::Union(sub_variants), super_variants) => {
                for sub_type in sub_variants {
                    self.unify_types(sub_type, super_variants, map, is_input);
                }
            }

            (sub_variants, Type::Union(super_variants)) => {
                for super_type in super_variants {
                    self.unify_types(sub_variants, super_type, map, is_input);
                }
            }

            (Type::List(sub_type), Type::List(super_type)) => {
                self.unify_types(sub_type, super_type, map, is_input)
            }

            (Type::Fn(sub_inputs, sub_output), Type::Fn(super_inputs, super_output)) => {
                if sub_inputs.len() != super_inputs.len() {
                    return;
                }

                for (sub_input, super_input) in sub_inputs.iter().zip(super_inputs) {
                    self.unify_types(super_input, sub_input, map, !is_input);
                }

                self.unify_types(sub_output, super_output, map, is_input);
            }

            (Type::Record(sub_fields), Type::Record(super_fields)) => {
                for super_field in super_fields {
                    if let Some(sub_field) = sub_fields.iter().find(|f| f.name == super_field.name)
                    {
                        self.unify_types(&sub_field.ty, &super_field.ty, map, is_input);
                    }
                }
            }

            (Type::Alias { alias_id, generics }, super_type) => {
                let sub_type = self.unit.instantiate_alias(*alias_id, generics);
                self.unify_types(&sub_type, super_type, map, is_input);
            }

            (sub_type, Type::Alias { alias_id, generics }) => {
                let super_type = self.unit.instantiate_alias(*alias_id, generics);
                self.unify_types(sub_type, &super_type, map, is_input);
            }

            (
                Type::Newtype {
                    newtype_id: sub_id,
                    generics: sub_generics,
                },
                Type::Newtype {
                    newtype_id: super_id,
                    generics: super_generics,
                },
            ) if sub_id == super_id => {
                assert_eq!(sub_generics.len(), super_generics.len());

                for (sub_type, super_type) in sub_generics.iter().zip(super_generics) {
                    self.unify_types(sub_type, super_type, map, is_input);
                }
            }

            (
                Type::Newtype {
                    newtype_id,
                    generics,
                },
                super_type,
            ) => {
                let sub_type = self.unit.instantiate_newtype(*newtype_id, generics);
                self.unify_types(&sub_type, super_type, map, is_input);
            }

            (_, _) => {}
        }
    }

    fn lower_binary_expr(&mut self, ast: &ast::Node, _ty: &Type) -> Expr {
        let op = match ast.token(1).unwrap() {
            Token::Plus => BinOp::Add,
            Token::Minus => BinOp::Sub,
            Token::Star => BinOp::Mul,
            Token::Slash => BinOp::Div,
            Token::Percent => BinOp::Mod,

            Token::Lt => BinOp::Lt,
            Token::Gt => BinOp::Gt,
            Token::LtEq => BinOp::Le,
            Token::GtEq => BinOp::Ge,

            Token::EqEq => BinOp::Eq,
            Token::BangEq => BinOp::Ne,

            token => unreachable!("{token:?}"),
        };

        let lhs = self.lower_expr(ast.node(0), &Type::Unknown);
        let rhs = self.lower_expr(ast.node(2), &Type::Unknown);

        use Type::{Bool, Error, Int, Nat, Num};

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

            BinOp::Lt | BinOp::Le | BinOp::Gt | BinOp::Ge => match (&lhs.ty, &rhs.ty) {
                (Nat | Int | Num, Nat | Int | Num) => Bool,

                (_, _) => Error,
            },

            BinOp::Eq | BinOp::Ne => {
                if self.unit.is_subtype_of(&lhs.ty, &rhs.ty)
                    || self.unit.is_subtype_of(&rhs.ty, &lhs.ty)
                {
                    Bool
                } else {
                    Error
                }
            }
        };

        if let Error = ty {
            let diagnostic = Diagnostic::error(format!(
                "operator `{op}` is not implemented for `{lhs}` and `{rhs}`",
                lhs = self.unit.format_type(&lhs.ty),
                rhs = self.unit.format_type(&rhs.ty),
            ))
            .label(ast.span, "in expression here");

            self.error(diagnostic);
        }

        let kind = ExprKind::Binary(op, Box::new(lhs), Box::new(rhs));
        let span = ast.span;

        Expr { kind, ty, span }
    }

    fn lower_record_expr(&mut self, ast: &ast::Node, ty: &Type) -> Expr {
        let fields = match ty {
            Type::Record(fields) => fields.as_slice(),
            _ => &[],
        };

        let mut expr_fields = Vec::new();
        let mut type_fields = Vec::new();

        for node in ast.nodes_of(ast::Kind::Field) {
            let Some(name) = node.string(0) else {
                continue;
            };

            let ty = fields
                .iter()
                .find(|f| f.name == name)
                .map(|f| &f.ty)
                .unwrap_or(&Type::Unknown);

            let value = self.lower_expr(node.node(2), ty);

            let type_field = TypeField {
                name: name.into(),
                ty:   value.ty.clone(),
            };

            let expr_field = ExprField {
                name: name.into(),
                expr: value,
            };

            type_fields.push(type_field);
            expr_fields.push(expr_field);
        }

        let kind = ExprKind::Record(expr_fields);
        let ty = Type::Record(type_fields);
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
