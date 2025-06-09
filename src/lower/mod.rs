use std::{
    collections::{HashMap, HashSet},
    mem,
    ops::{Deref, DerefMut},
};

use crate::{
    ast,
    diagnostic::{Diagnostic, Emitter, Span},
    ir::untyped as ir,
};

#[derive(Clone, Debug)]
pub struct LowerError;

struct Newtype {
    ast: ast::Newtype,
    module: ir::Mid,
    submodule: ir::Mid,
}

struct Extern {
    ast: ast::Extern,
    module: ir::Mid,
}

struct Function {
    ast: ast::Function,
    module: ir::Mid,
}

pub struct Lowerer<'a> {
    emitter: &'a mut dyn Emitter,
    ir: ir::Program,

    call_graph: HashMap<ir::Bid, HashSet<ir::Bid>>,
    externs: HashMap<ir::Bid, Extern>,
    newtypes: HashMap<ir::Tid, Newtype>,
    functions: HashMap<ir::Bid, Function>,
    ascriptions: Vec<(ir::Mid, ast::Ascription)>,
}

impl<'a> Lowerer<'a> {
    pub fn new(emitter: &'a mut dyn Emitter) -> Self {
        Lowerer {
            emitter,
            ir: ir::Program::default(),

            call_graph: HashMap::new(),
            externs: HashMap::new(),
            newtypes: HashMap::new(),
            functions: HashMap::new(),
            ascriptions: Vec::new(),
        }
    }

    pub fn create_module<'s>(&mut self, path: impl Iterator<Item = &'s str>) -> ir::Mid {
        self.create_module_from(self.ir.root, path)
    }

    fn create_module_from<'s>(
        &mut self,
        from: ir::Mid,
        path: impl Iterator<Item = &'s str>,
    ) -> ir::Mid {
        let mut module = from;

        for segment in path {
            match self.ir[module].modules.get(segment) {
                Some(&submodule) => module = submodule,
                None => {
                    let submodule = self.ir.push_module(ir::Module::default());
                    (self.ir[module].modules).insert(segment.to_string(), submodule);
                    module = submodule;
                }
            }
        }

        module
    }

    pub fn add_module(&mut self, path: &[&str], ast: ast::Module) -> Result<(), LowerError> {
        let module = self.create_module(path.iter().copied());

        for item in ast.items {
            match item {
                ast::Item::Import(ast) => {
                    let name = ast.path.name().to_string();
                    self.ir[module].imports.insert(name, ast.path.segments);
                }

                ast::Item::Newtype(ast) => {
                    let kind = match ast.kind {
                        ast::NewtypeKind::Union(_) => {
                            let union = ir::Union {
                                variants: Vec::new(),
                            };
                            ir::NewtypeKind::Union(union)
                        }

                        ast::NewtypeKind::Record(_) => {
                            let record = ir::Record { fields: Vec::new() };
                            ir::NewtypeKind::Record(record)
                        }
                    };

                    let mut generics = Vec::new();

                    for param in ast.generics.iter() {
                        let var = ir::Var::fresh();
                        generics.push((param.clone(), var));
                    }

                    let newtype = ir::Newtype {
                        name: ast.name.to_string(),
                        generics,
                        kind,
                    };

                    let tid = self.ir.tcx.push_newtype(newtype);

                    let submodule = self.create_module_from(module, ast.name.modules());

                    if let ast::NewtypeKind::Union(ref variants) = ast.kind {
                        for variant in variants {
                            let name = variant.name.clone();
                            let variant = (tid, name.clone());

                            let existing =
                                self.ir[submodule].variants.insert(name.clone(), variant);

                            if existing.is_some() {
                                let diagnostic = Diagnostic::error(format!(
                                    "duplicate variant '{}' in module '{}'",
                                    name, ast.name
                                ))
                                .with_label(ast.span, "found here");

                                self.emitter.emit(diagnostic);
                                return Err(LowerError);
                            }

                            let body = ir::Body {
                                name: String::new(),
                                locals: ir::Locals::default(),
                                inputs: Vec::new(),
                                expr: None,
                                ty: ir::Type::unit(),
                            };

                            let bid = self.ir.bodies.push(body);
                            let existing = self.ir[submodule].bodies.insert(name.clone(), bid);

                            if existing.is_some() {
                                let diagnostic = Diagnostic::error(format!(
                                    "duplicate body '{}' in module '{}'",
                                    name, ast.name
                                ))
                                .with_label(ast.span, "found here");

                                self.emitter.emit(diagnostic);
                                return Err(LowerError);
                            }
                        }
                    }

                    let existing =
                        (self.ir[submodule].newtypes).insert(ast.name.name().to_string(), tid);

                    if existing.is_some() {
                        let diagnostic = Diagnostic::error(format!(
                            "duplicate newtype '{}' in module '{}'",
                            ast.name, ast.name
                        ))
                        .with_label(ast.span, "found here");

                        self.emitter.emit(diagnostic);
                        return Err(LowerError);
                    }

                    let newtype = Newtype {
                        ast,
                        module,
                        submodule,
                    };

                    self.newtypes.insert(tid, newtype);
                }

                ast::Item::Function(ast) => {
                    let body = ir::Body {
                        name: ast.name.to_string(),
                        locals: ir::Locals::default(),
                        inputs: Vec::new(),
                        expr: None,
                        ty: ir::Type::infer(),
                    };

                    let bid = self.ir.bodies.push(body.clone());

                    let submodule = self.create_module_from(module, ast.name.modules());
                    let existing =
                        (self.ir[submodule].bodies).insert(ast.name.name().to_string(), bid);

                    if existing.is_some() {
                        let diagnostic = Diagnostic::error(format!(
                            "duplicate function '{}' in module '{}'",
                            ast.name, ast.name
                        ))
                        .with_label(ast.name.span, "found here");

                        self.emitter.emit(diagnostic);
                        return Err(LowerError);
                    }

                    self.functions.insert(bid, Function { ast, module });
                }

                ast::Item::Extern(ast) => {
                    let body = ir::Body {
                        name: ast.name.to_string(),
                        locals: ir::Locals::default(),
                        inputs: Vec::new(),
                        expr: None,
                        ty: ir::Type::infer(),
                    };

                    let bid = self.ir.bodies.push(body.clone());

                    let submodule = self.create_module_from(module, ast.name.modules());
                    let existing =
                        (self.ir[submodule].bodies).insert(ast.name.name().to_string(), bid);

                    if existing.is_some() {
                        let diagnostic = Diagnostic::error(format!(
                            "duplicate extern '{}' in module '{}'",
                            ast.name, ast.name
                        ))
                        .with_label(ast.name.span, "found here");

                        self.emitter.emit(diagnostic);
                        return Err(LowerError);
                    }

                    self.externs.insert(bid, Extern { ast, module });
                }

                ast::Item::Ascription(ast) => {
                    self.ascriptions.push((module, ast));
                }
            }
        }

        Ok(())
    }

    pub fn finish(mut self) -> Result<ir::Program, LowerError> {
        self.import_root_modules();
        self.resolve_imports()?;
        self.lower_newtypes()?;
        self.lower_externs()?;

        while let Some(bid) = self.functions.keys().next().copied() {
            self.lower_function(bid)?;
        }

        for (module, ascription) in mem::take(&mut self.ascriptions) {
            let mut generics = Vec::new();
            let mut type_lowerer = TypeLowerer {
                lowerer: &mut self,
                module,
                generics: Generics::Extendable(&mut generics),
                allow_inferred: false,
            };

            let expected = type_lowerer.lower_type(ascription.ty)?;

            let Some(module) = self.ir.get_module(module, ascription.name.modules()) else {
                panic!();
            };

            let bid = self.ir[module].bodies[ascription.name.name()];
            let ty = self.ir[bid].ty.clone();

            self.ir.tcx.unify(ty, expected, ascription.span);
        }

        self.ir.tcx.finish(self.emitter).map_err(|_| LowerError)?;

        Ok(self.ir)
    }

    fn import_root_modules(&mut self) {
        for (name, submodule) in self.ir[self.ir.root].modules.clone() {
            for module in self.ir.modules.iter_mut() {
                module.modules.insert(name.clone(), submodule);
            }
        }
    }

    fn resolve_imports(&mut self) -> Result<(), LowerError> {
        for i in 0..self.ir.modules.len() {
            while let Some(name) = self.ir.modules[i].imports.keys().next().cloned() {
                let path = self.ir.modules[i].imports.remove(&name).unwrap();

                self.resolve_import(i, &path)?;
            }
        }

        Ok(())
    }

    fn resolve_import(&mut self, module: usize, path: &[String]) -> Result<(), LowerError> {
        let mut current = module;

        for segment in &path[0..path.len() - 1] {
            if let Some(path) = self.ir.modules[current].imports.remove(segment) {
                self.resolve_import(current, &path)?;
            }

            let Some(&submodule) = self.ir.modules[current].modules.get(segment) else {
                let diagnostic = Diagnostic::error(format!("unresolved module: {}", segment));

                self.emitter.emit(diagnostic);
                return Err(LowerError);
            };

            current = submodule.index() as usize;
        }

        let last = path.last().unwrap();

        if let Some(path) = self.ir.modules[current].imports.remove(last) {
            self.resolve_import(current, &path)?;
        }

        let mut imported = false;

        if let Some(&submodule) = self.ir.modules[current].modules.get(last) {
            (self.ir.modules[module].modules).insert(last.to_string(), submodule);

            imported = true;
        }

        if let Some(&bid) = self.ir.modules[current].bodies.get(last) {
            self.ir.modules[module].bodies.insert(last.to_string(), bid);

            imported = true;
        }

        if let Some(&tid) = self.ir.modules[current].newtypes.get(last) {
            (self.ir.modules[module].newtypes).insert(last.to_string(), tid);

            imported = true;
        }

        if let Some(variant) = self.ir.modules[current].variants.get(last).cloned() {
            (self.ir.modules[module].variants).insert(last.to_string(), variant);

            imported = true;
        }

        if !imported {
            let diagnostic = Diagnostic::error(format!("unresolved import: {}", last));

            self.emitter.emit(diagnostic);
            return Err(LowerError);
        }

        Ok(())
    }

    fn lower_newtypes(&mut self) -> Result<(), LowerError> {
        for (tid, newtype) in mem::take(&mut self.newtypes) {
            let generics = self.ir.tcx[tid].generics.clone();

            let mut type_lowerer = TypeLowerer {
                lowerer: self,
                module: newtype.module,
                generics: Generics::Defined(&generics),
                allow_inferred: false,
            };

            match newtype.ast.kind {
                ast::NewtypeKind::Union(variants) => {
                    let mut union = ir::Union {
                        variants: Vec::new(),
                    };

                    for variant in variants {
                        let ty = match variant.ty {
                            Some(ty) => Some(type_lowerer.lower_type(ty)?),
                            None => None,
                        };

                        let generics = (0..generics.len())
                            .map(|_| ir::Type::infer())
                            .collect::<Vec<_>>();

                        let body = match ty {
                            Some(ref ty) => {
                                let subst = type_lowerer.ir.tcx[tid]
                                    .generics
                                    .iter()
                                    .map(|(_, var)| *var)
                                    .zip(generics.clone())
                                    .collect::<HashMap<_, _>>();

                                let ty = ty.clone().substitute(&subst);

                                let mut locals = ir::Locals::default();
                                let lid = locals.push(ir::Local {
                                    name: variant.name.clone(),
                                    ty: ty.clone(),
                                });

                                let output_ty = ir::Type::newtype(tid, generics);
                                let function_ty = ir::Type::function(ty.clone(), output_ty.clone());

                                ir::Body {
                                    name: variant.name.clone(),
                                    locals,
                                    inputs: vec![ir::Pattern {
                                        kind: ir::PatternKind::Binding(lid),
                                        span: variant.span,
                                    }],
                                    expr: Some(ir::Expr {
                                        kind: ir::ExprKind::Variant(
                                            variant.name.to_string(),
                                            Some(Box::new(ir::Expr {
                                                kind: ir::ExprKind::Local(lid),
                                                span: variant.span,
                                                ty,
                                            })),
                                        ),
                                        span: variant.span,
                                        ty: output_ty,
                                    }),
                                    ty: function_ty,
                                }
                            }

                            None => ir::Body {
                                name: variant.name.clone(),
                                locals: ir::Locals::default(),
                                inputs: Vec::new(),
                                expr: Some(ir::Expr {
                                    kind: ir::ExprKind::Variant(variant.name.clone(), None),
                                    span: variant.span,
                                    ty: ir::Type::newtype(tid, generics.clone()),
                                }),
                                ty: ir::Type::newtype(tid, generics),
                            },
                        };

                        type_lowerer.ir[newtype.submodule]
                            .variants
                            .insert(variant.name.clone(), (tid, variant.name.clone()));

                        let bid = type_lowerer.ir[newtype.submodule].bodies[&variant.name];
                        type_lowerer.ir.bodies[bid] = body;

                        let value = ir::Variant {
                            name: variant.name,
                            ty,
                        };

                        union.variants.push(value);
                    }

                    let kind = ir::NewtypeKind::Union(union);
                    self.ir.tcx[tid].kind = kind;
                }

                ast::NewtypeKind::Record(fields) => {
                    let mut record = ir::Record { fields: Vec::new() };

                    for field in fields {
                        let ty = type_lowerer.lower_type(field.ty)?;

                        let value = ir::Field {
                            name: field.name,
                            ty,
                        };

                        record.fields.push(value);
                    }

                    let kind = ir::NewtypeKind::Record(record);
                    self.ir.tcx[tid].kind = kind;
                }
            }
        }

        Ok(())
    }

    fn lower_externs(&mut self) -> Result<(), LowerError> {
        for (bid, Extern { ast, module }) in mem::take(&mut self.externs) {
            let mut generics = Vec::new();
            let mut type_lowerer = TypeLowerer {
                lowerer: self,
                module,
                generics: Generics::Extendable(&mut generics),
                allow_inferred: false,
            };

            let expected = type_lowerer.lower_type(ast.ty)?;
            let ty = self.ir[bid].ty.clone();

            self.ir.tcx.unify(ty, expected, ast.span);
        }

        Ok(())
    }

    fn lower_function(&mut self, bid: ir::Bid) -> Result<(), LowerError> {
        let Some(function) = self.functions.remove(&bid) else {
            return Ok(());
        };

        let mut lowerer = ExprLowerer {
            lowerer: self,

            body: bid,
            module: function.module,

            scope: Vec::new(),
            parents: Vec::new(),
        };

        let mut params = Vec::new();
        for pattern in function.ast.params {
            let ty = ir::Type::infer();
            params.push(ty.clone());

            let pattern = lowerer.lower_pattern(pattern, ty)?;
            lowerer.body_mut().inputs.push(pattern);
        }

        if let Some(body) = function.ast.body {
            let body = lowerer.lower_expr(body)?;

            let ty = params
                .into_iter()
                .rfold(body.ty.clone(), |o, i| ir::Type::function(i, o));

            lowerer.unify(ty, lowerer.body().ty.clone(), body.span);
            lowerer.body_mut().expr = Some(body);
        }

        Ok(())
    }
}

enum Generics<'a> {
    Defined(&'a [(String, ir::Var)]),
    Extendable(&'a mut Vec<(String, ir::Var)>),
}

struct TypeLowerer<'a, 'b> {
    lowerer: &'a mut Lowerer<'b>,
    module: ir::Mid,
    generics: Generics<'a>,
    allow_inferred: bool,
}

impl TypeLowerer<'_, '_> {
    fn lower_type(&mut self, ast: ast::Type) -> Result<ir::Type, LowerError> {
        Ok(match ast.kind {
            ast::TypeKind::Int => ir::Type::int(),
            ast::TypeKind::Str => ir::Type::str(),
            ast::TypeKind::Bool => ir::Type::bool(),
            ast::TypeKind::Unit => ir::Type::unit(),

            ast::TypeKind::Path(path) => {
                let Some(module) = self.ir.get_module(self.module, path.modules()) else {
                    let diagnostic = Diagnostic::error(format!("unresolved module: {}", path))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                let Some(&tid) = self.ir[module].newtypes.get(path.name()) else {
                    let diagnostic = Diagnostic::error(format!("unresolved type: {}", path))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                if path.generics.len() != self.ir.tcx[tid].generics.len() {
                    let diagnostic = Diagnostic::error(format!(
                        "wrong number of type parameters for '{}': expected {}, found {}",
                        path,
                        self.ir.tcx[tid].generics.len(),
                        path.generics.len()
                    ))
                    .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                }

                let generics = path
                    .generics
                    .into_iter()
                    .map(|ty| self.lower_type(ty))
                    .collect::<Result<Vec<_>, _>>()?;

                ir::Type::newtype(tid, generics)
            }

            ast::TypeKind::List(item) => {
                let item = self.lower_type(*item)?;
                ir::Type::list(item)
            }

            ast::TypeKind::Tuple(fields) => {
                let fields = fields
                    .into_iter()
                    .map(|ty| self.lower_type(ty))
                    .collect::<Result<Vec<_>, _>>()?;

                ir::Type::tuple(fields)
            }

            ast::TypeKind::Function(input, output) => {
                let input = self.lower_type(*input)?;
                let output = self.lower_type(*output)?;

                ir::Type::function(input, output)
            }

            ast::TypeKind::Generic(name) => {
                match &mut self.generics {
                    Generics::Defined(generics) => {
                        if let Some((_, var)) = generics.iter().find(|(n, _)| n == &name) {
                            return Ok(ir::Type::Var(*var));
                        }
                    }

                    Generics::Extendable(generics) => {
                        let var = ir::Var::fresh();
                        generics.push((name, var));
                        return Ok(ir::Type::Var(var));
                    }
                }

                let diagnostic = Diagnostic::error(format!("unresolved generic type: {}", name))
                    .with_label(ast.span, "found here");

                self.lowerer.emitter.emit(diagnostic);
                return Err(LowerError);
            }

            ast::TypeKind::Inferred => {
                if !self.allow_inferred {
                    let diagnostic = Diagnostic::error("inferred type not allowed")
                        .with_label(ast.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                }

                ir::Type::infer()
            }
        })
    }
}

impl<'b> Deref for TypeLowerer<'_, 'b> {
    type Target = Lowerer<'b>;

    fn deref(&self) -> &Self::Target {
        self.lowerer
    }
}

impl DerefMut for TypeLowerer<'_, '_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.lowerer
    }
}

type ParentScope = (ir::Bid, Vec<(ir::Lid, Option<ir::Lid>)>);

struct ExprLowerer<'a, 'b> {
    lowerer: &'a mut Lowerer<'b>,
    body: ir::Bid,
    module: ir::Mid,
    scope: Vec<ir::Lid>,
    parents: Vec<ParentScope>,
}

impl ExprLowerer<'_, '_> {
    fn body(&self) -> &ir::Body {
        &self.lowerer.ir[self.body]
    }

    fn body_mut(&mut self) -> &mut ir::Body {
        &mut self.lowerer.ir[self.body]
    }

    fn capture_local<'p>(
        ir: &mut ir::Program,
        mut parents: impl Iterator<Item = &'p mut ParentScope>,
        current: ir::Bid,
        name: &str,
    ) -> Option<ir::Lid> {
        let (bid, scope) = parents.next()?;

        if let Some((lid, capture)) = scope
            .iter_mut()
            .rev()
            .find(|(lid, _)| ir.bodies[*bid].locals[*lid].name == name)
        {
            if let Some(lid) = capture {
                return Some(*lid);
            }

            let local = ir.bodies[*bid].locals[*lid].clone();
            let captured = ir.bodies[current].locals.push(local);
            *capture = Some(captured);

            return Some(captured);
        }

        let lid = Self::capture_local(ir, parents, *bid, name)?;

        let local = ir.bodies[*bid].locals[lid].clone();
        let captured = ir.bodies[current].locals.push(local);

        scope.push((lid, Some(captured)));

        Some(captured)
    }

    fn find_local(&mut self, name: &str) -> Option<ir::Lid> {
        if let Some(lid) = self
            .scope
            .iter()
            .copied()
            .rev()
            .find(|&lid| self.body().locals[lid].name == name)
        {
            return Some(lid);
        }

        Self::capture_local(
            &mut self.lowerer.ir,
            self.parents.iter_mut().rev(),
            self.body,
            name,
        )
    }

    fn number(&mut self, ty: ir::Type, span: Span) {
        self.lowerer.ir.tcx.number(ty, span);
    }

    fn unify(&mut self, lhs: ir::Type, rhs: ir::Type, span: Span) {
        self.lowerer.ir.tcx.unify(lhs, rhs, span);
    }

    fn field(&mut self, target: ir::Type, name: &str, ty: ir::Type, span: Span) {
        self.lowerer.ir.tcx.field(target, name, ty, span);
    }

    fn lower_type(&mut self, ast: ast::Type) -> Result<ir::Type, LowerError> {
        let mut type_lowerer = TypeLowerer {
            lowerer: self.lowerer,
            module: self.module,
            generics: Generics::Defined(&[]),
            allow_inferred: true,
        };

        type_lowerer.lower_type(ast)
    }

    fn lower_pattern(
        &mut self,
        ast: ast::Pattern,
        ty: ir::Type,
    ) -> Result<ir::Pattern, LowerError> {
        Ok(match ast.kind {
            ast::PatternKind::Wildcard => ir::Pattern {
                kind: ir::PatternKind::Wildcard,
                span: ast.span,
            },

            ast::PatternKind::Path(path) => {
                if let Some(module) = self.ir.get_module(self.module, path.modules()) {
                    if let Some((tid, variant)) = self.ir[module].variants.get(path.name()).cloned()
                    {
                        let generics = (0..self.ir.tcx[tid].generics.len())
                            .map(|_| ir::Type::infer())
                            .collect::<Vec<_>>();

                        let union_ty = ir::Type::newtype(tid, generics);
                        self.unify(union_ty.clone(), ty, ast.span);

                        let kind = ir::PatternKind::Variant(union_ty, variant, None);
                        return Ok(ir::Pattern {
                            kind,
                            span: ast.span,
                        });
                    }
                }

                if path.segments.len() != 1 {
                    let diagnostic = Diagnostic::error(format!(
                        "invalid pattern path: '{}', expected a single segment",
                        path
                    ))
                    .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                }

                let lid = self.body_mut().locals.push(ir::Local {
                    name: path.name().to_string(),
                    ty: ty.clone(),
                });

                self.scope.push(lid);

                ir::Pattern {
                    kind: ir::PatternKind::Binding(lid),
                    span: ast.span,
                }
            }

            ast::PatternKind::Variant(path, pattern) => {
                let Some(module) = self.ir.get_module(self.module, path.modules()) else {
                    let diagnostic = Diagnostic::error(format!("unresolved module: {}", path))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                let Some((tid, variant)) = self.ir[module].variants.get(path.name()).cloned()
                else {
                    let diagnostic = Diagnostic::error(format!("unresolved variant: {}", path))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                let generics = (0..self.ir.tcx[tid].generics.len())
                    .map(|_| ir::Type::infer())
                    .collect::<Vec<_>>();

                let subst = self.ir.tcx[tid]
                    .generics
                    .iter()
                    .map(|(_, var)| *var)
                    .zip(generics.clone())
                    .collect::<HashMap<_, _>>();

                let newtype = &self.ir.tcx[tid];
                let ir::NewtypeKind::Union(ref union) = newtype.kind else {
                    unreachable!();
                };

                let variant_ty = {
                    let variant = union
                        .variants
                        .iter()
                        .find(|v| v.name == variant)
                        .expect("variant not found in union");

                    match variant.ty {
                        Some(ref ty) => ty.clone().substitute(&subst),
                        None => {
                            let diagnostic = Diagnostic::error(format!(
                                "variant '{}' in union '{}' does not have a type",
                                variant.name, newtype.name
                            ));

                            self.lowerer.emitter.emit(diagnostic);
                            return Err(LowerError);
                        }
                    }
                };

                let union_ty = ir::Type::newtype(tid, generics);
                self.unify(union_ty.clone(), ty, ast.span);

                let pattern = self.lower_pattern(*pattern, variant_ty)?;

                let kind = ir::PatternKind::Variant(union_ty, variant, Some(Box::new(pattern)));
                ir::Pattern {
                    kind,
                    span: ast.span,
                }
            }

            ast::PatternKind::Tuple(items) => {
                let mut types = Vec::new();
                let mut patterns = Vec::new();

                for item in items {
                    let item_ty = ir::Type::infer();
                    let item_pattern = self.lower_pattern(item, item_ty.clone())?;

                    types.push(item_ty);
                    patterns.push(item_pattern);
                }

                let tuple_ty = ir::Type::tuple(types);
                self.unify(ty, tuple_ty, ast.span);

                ir::Pattern {
                    kind: ir::PatternKind::Tuple(patterns),
                    span: ast.span,
                }
            }

            ast::PatternKind::Bool(value) => {
                self.unify(ty, ir::Type::bool(), ast.span);

                ir::Pattern {
                    kind: ir::PatternKind::Bool(value),
                    span: ast.span,
                }
            }

            ast::PatternKind::List(items, rest) => {
                let item_ty = ir::Type::infer();
                let list_ty = ir::Type::list(item_ty.clone());

                self.unify(ty, list_ty.clone(), ast.span);

                let mut pattern = match rest {
                    Some(rest) => self.lower_pattern(*rest, list_ty.clone())?,
                    None => ir::Pattern {
                        kind: ir::PatternKind::ListEmpty,
                        span: ast.span,
                    },
                };

                for item in items.into_iter().rev() {
                    let item_pattern = self.lower_pattern(item, item_ty.clone())?;

                    let span = item_pattern.span;
                    let kind = ir::PatternKind::ListCons(Box::new(item_pattern), Box::new(pattern));
                    pattern = ir::Pattern { kind, span };
                }

                pattern
            }
        })
    }

    fn lower_expr(&mut self, expr: ast::Expr) -> Result<ir::Expr, LowerError> {
        Ok(match expr.kind {
            ast::ExprKind::Int(value) => ir::Expr {
                kind: ir::ExprKind::Int(value),
                span: expr.span,
                ty: ir::Type::int(),
            },

            ast::ExprKind::Bool(value) => ir::Expr {
                kind: ir::ExprKind::Bool(value),
                span: expr.span,
                ty: ir::Type::bool(),
            },

            ast::ExprKind::String(value) => ir::Expr {
                kind: ir::ExprKind::String(value),
                span: expr.span,
                ty: ir::Type::str(),
            },

            ast::ExprKind::Path(path) => {
                if path.segments.len() == 1 {
                    if let Some(lid) = self.find_local(path.name()) {
                        return Ok(ir::Expr {
                            kind: ir::ExprKind::Local(lid),
                            span: expr.span,
                            ty: self.body().locals[lid].ty.clone(),
                        });
                    }
                }

                let name = path.segments.last().unwrap();
                let len = path.segments.len();
                let path = path.segments.iter().take(len - 1).map(String::as_str);

                let module = self.ir.get_module(self.module, path);

                if let Some(module) = module {
                    if let Some(&bid) = self.ir[module].bodies.get(name) {
                        let this_bid = self.body;

                        let called_from = self.call_graph.entry(bid).or_default();
                        called_from.insert(this_bid);

                        self.lower_function(bid)?;

                        let callers = self.call_graph.get(&this_bid).cloned().unwrap_or_default();
                        let called_from = self.call_graph.entry(bid).or_default();
                        called_from.extend(callers);

                        let mut ty = self.ir[bid].ty.clone();
                        ty = self.ir.tcx.substitute(ty);

                        if (self.call_graph.get(&this_bid)).is_none_or(|c| !c.contains(&bid)) {
                            ty = self.ir.tcx.instantiate(ty);
                        }

                        return Ok(ir::Expr {
                            kind: ir::ExprKind::Body(bid),
                            span: expr.span,
                            ty,
                        });
                    }
                }

                let diagnostic = Diagnostic::error(format!("unresolved path: {}", name))
                    .with_label(expr.span, "found here");

                self.lowerer.emitter.emit(diagnostic);

                return Err(LowerError);
            }

            ast::ExprKind::Let(pattern, expr) => {
                let span = expr.span;
                let value = self.lower_expr(*expr)?;
                let pattern = self.lower_pattern(pattern, value.ty.clone())?;

                if pattern.kind.is_refutable() {
                    let diagnostic = Diagnostic::error("refutable pattern in let binding")
                        .with_label(pattern.span, "pattern is refutable")
                        .with_label(value.span, "value is here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                }

                ir::Expr {
                    kind: ir::ExprKind::Let(pattern, Box::new(value)),
                    span,
                    ty: ir::Type::unit(),
                }
            }

            ast::ExprKind::Record(path, fields) => {
                let Some(module) = self.ir.get_module(self.module, path.modules()) else {
                    let diagnostic = Diagnostic::error(format!("unresolved module: {}", path))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                let Some(&tid) = self.ir[module].newtypes.get(path.name()) else {
                    let diagnostic = Diagnostic::error(format!("unresolved type: {}", path))
                        .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                };

                let newtype = &self.ir.tcx[tid];
                if path.generics.len() > newtype.generics.len() {
                    let diagnostic = Diagnostic::error(format!(
                        "too many type parameters for '{}': expected {}, found {}",
                        path,
                        newtype.generics.len(),
                        path.generics.len()
                    ))
                    .with_label(path.span, "found here");

                    self.lowerer.emitter.emit(diagnostic);
                    return Err(LowerError);
                }

                let mut generics = Vec::new();

                for ty in path.generics.clone() {
                    let ty = self.lower_type(ty)?;
                    generics.push(ty);
                }

                let newtype = self.ir.tcx[tid].clone();
                let ir::NewtypeKind::Record(record) = newtype.kind else {
                    unreachable!();
                };

                for _ in 0..newtype.generics.len() - generics.len() {
                    generics.push(ir::Type::infer());
                }

                let subst = newtype
                    .generics
                    .iter()
                    .map(|(_, var)| *var)
                    .zip(generics.clone())
                    .collect::<HashMap<_, _>>();

                let mut ir_fields = Vec::new();

                for (name, value) in fields {
                    let value = self.lower_expr(value)?;

                    let Some(field) = record.field(&name) else {
                        let diagnostic = Diagnostic::error(format!(
                            "type '{}' does not have field '{}'",
                            path, name
                        ))
                        .with_label(value.span, "found here");

                        self.lowerer.emitter.emit(diagnostic);
                        return Err(LowerError);
                    };

                    let ty = field.ty.clone().substitute(&subst);
                    self.unify(value.ty.clone(), ty.clone(), value.span);

                    if ir_fields.iter().any(|(n, _)| n == &name) {
                        let diagnostic =
                            Diagnostic::error(format!("duplicate field '{}' in record", name))
                                .with_label(value.span, "found here");

                        self.lowerer.emitter.emit(diagnostic);
                        return Err(LowerError);
                    }

                    ir_fields.push((name, value));
                }

                for field in record.fields.iter() {
                    if !ir_fields.iter().any(|(n, _)| n == &field.name) {
                        let diagnostic = Diagnostic::error(format!(
                            "missing field '{}' in record '{}'",
                            field.name, path
                        ))
                        .with_label(expr.span, "found here");

                        self.lowerer.emitter.emit(diagnostic);
                        return Err(LowerError);
                    }
                }

                let span = expr.span;
                let ty = ir::Type::newtype(tid, generics);
                let kind = ir::ExprKind::Record(ir_fields);
                ir::Expr { kind, span, ty }
            }

            ast::ExprKind::List(items, rest) => {
                let item_ty = ir::Type::infer();
                let list_ty = ir::Type::list(item_ty.clone());

                let mut expr = match rest {
                    Some(rest) => self.lower_expr(*rest)?,
                    None => ir::Expr {
                        kind: ir::ExprKind::ListEmpty,
                        span: expr.span,
                        ty: list_ty.clone(),
                    },
                };

                self.unify(expr.ty.clone(), list_ty.clone(), expr.span);

                for item in items.into_iter().rev() {
                    let item_expr = self.lower_expr(item)?;

                    self.unify(item_expr.ty.clone(), item_ty.clone(), expr.span);

                    let span = item_expr.span;
                    let kind = ir::ExprKind::ListCons(Box::new(item_expr), Box::new(expr));
                    expr = ir::Expr {
                        kind,
                        span,
                        ty: list_ty.clone(),
                    };
                }

                expr
            }

            ast::ExprKind::Tuple(items) => {
                let mut types = Vec::new();
                let mut exprs = Vec::new();

                for item in items {
                    let item = self.lower_expr(item)?;
                    types.push(item.ty.clone());
                    exprs.push(item);
                }

                let span = expr.span;
                let ty = ir::Type::tuple(types);
                let kind = ir::ExprKind::Tuple(exprs);
                ir::Expr { kind, span, ty }
            }

            ast::ExprKind::Call(callee, input) => {
                let input = self.lower_expr(*input)?;
                let callee = self.lower_expr(*callee)?;

                let output = ir::Type::infer();
                let function = ir::Type::function(input.ty.clone(), output.clone());
                self.unify(callee.ty.clone(), function.clone(), expr.span);

                ir::Expr {
                    kind: ir::ExprKind::Call(Box::new(callee), Box::new(input)),
                    span: expr.span,
                    ty: output,
                }
            }

            ast::ExprKind::Lambda(params, expr) => {
                let body = ir::Body {
                    name: format!("{}::{{lambda}}", self.body().name),
                    locals: ir::Locals::default(),
                    inputs: Vec::new(),
                    expr: None,
                    ty: ir::Type::unit(),
                };

                let bid = self.ir.bodies.push(body);

                let mut lowerer = ExprLowerer {
                    lowerer: self.lowerer,
                    body: bid,
                    module: self.module,
                    scope: Vec::new(),
                    parents: self.parents.clone(),
                };

                let scope = self.scope.iter().map(|&lid| (lid, None)).collect();
                lowerer.parents.push((self.body, scope));

                let mut patterns = Vec::new();

                for param in params {
                    let ty = ir::Type::infer();
                    let pattern = lowerer.lower_pattern(param, ty.clone())?;

                    if pattern.kind.is_refutable() {
                        let diagnostic = Diagnostic::error("refutable pattern in lambda")
                            .with_label(pattern.span, "pattern is refutable");

                        lowerer.lowerer.emitter.emit(diagnostic);
                        return Err(LowerError);
                    }

                    patterns.push((pattern, ty));
                }

                let expr = lowerer.lower_expr(*expr)?;
                let mut types = Vec::new();

                let (_, parent) = lowerer.parents.pop().unwrap();
                for (_, captured) in parent.iter().cloned() {
                    let Some(captured) = captured else { continue };

                    let pattern = ir::Pattern {
                        kind: ir::PatternKind::Binding(captured),
                        span: expr.span,
                    };

                    lowerer.body_mut().inputs.push(pattern);

                    let capture = lowerer.body().locals[captured].ty.clone();
                    types.push(capture);
                }

                for (pattern, input) in patterns {
                    lowerer.body_mut().inputs.push(pattern);
                    types.push(input);
                }

                let mut ty = types
                    .into_iter()
                    .rfold(expr.ty.clone(), |o, i| ir::Type::function(i, o));

                let span = expr.span;
                lowerer.body_mut().expr = Some(expr);
                lowerer.body_mut().ty = ty.clone();

                self.parents = lowerer.parents;

                let mut expr = ir::Expr {
                    kind: ir::ExprKind::Body(bid),
                    ty: ty.clone(),
                    span,
                };

                for (lid, captured) in parent {
                    let Some(_) = captured else { continue };

                    let input = ir::Expr {
                        kind: ir::ExprKind::Local(lid),
                        ty: self.body().locals[lid].ty.clone(),
                        span,
                    };

                    let kind = ir::ExprKind::Call(Box::new(expr), Box::new(input));

                    let ir::Type::App(ir::App::Function(_, output)) = ty else {
                        unreachable!();
                    };

                    ty = *output;
                    expr = ir::Expr {
                        kind,
                        span,
                        ty: ty.clone(),
                    };
                }

                expr
            }

            ast::ExprKind::Binary(op, lhs, rhs) => {
                let op = match op {
                    ast::BinOp::Add => ir::BinOp::Add,
                    ast::BinOp::Sub => ir::BinOp::Sub,
                    ast::BinOp::Mul => ir::BinOp::Mul,
                    ast::BinOp::Div => ir::BinOp::Div,
                    ast::BinOp::Mod => ir::BinOp::Mod,
                    ast::BinOp::And => ir::BinOp::And,
                    ast::BinOp::Or => ir::BinOp::Or,
                    ast::BinOp::Gt => ir::BinOp::Gt,
                    ast::BinOp::Lt => ir::BinOp::Lt,
                    ast::BinOp::Ge => ir::BinOp::Ge,
                    ast::BinOp::Le => ir::BinOp::Le,
                    ast::BinOp::Eq => ir::BinOp::Eq,
                    ast::BinOp::Ne => ir::BinOp::Ne,
                };

                let lhs = self.lower_expr(*lhs)?;
                let rhs = self.lower_expr(*rhs)?;

                let ty = match op {
                    ir::BinOp::Add
                    | ir::BinOp::Sub
                    | ir::BinOp::Mul
                    | ir::BinOp::Div
                    | ir::BinOp::Mod => {
                        self.unify(lhs.ty.clone(), rhs.ty.clone(), expr.span);
                        self.number(lhs.ty.clone(), expr.span);

                        lhs.ty.clone()
                    }

                    ir::BinOp::Gt | ir::BinOp::Lt | ir::BinOp::Ge | ir::BinOp::Le => {
                        self.unify(lhs.ty.clone(), rhs.ty.clone(), expr.span);
                        self.number(lhs.ty.clone(), expr.span);

                        ir::Type::bool()
                    }

                    ir::BinOp::Eq | ir::BinOp::Ne => {
                        self.unify(lhs.ty.clone(), rhs.ty.clone(), expr.span);

                        ir::Type::bool()
                    }

                    ir::BinOp::And | ir::BinOp::Or => {
                        self.unify(lhs.ty.clone(), ir::Type::bool(), expr.span);
                        self.unify(rhs.ty.clone(), ir::Type::bool(), expr.span);

                        ir::Type::bool()
                    }
                };

                let span = expr.span;
                let kind = ir::ExprKind::Binary(op, Box::new(lhs), Box::new(rhs));
                ir::Expr { kind, span, ty }
            }

            ast::ExprKind::Field(target, name) => {
                let target = self.lower_expr(*target)?;

                let ty = ir::Type::infer();
                self.field(target.ty.clone(), &name, ty.clone(), expr.span);

                ir::Expr {
                    kind: ir::ExprKind::Field(Box::new(target), name),
                    span: expr.span,
                    ty,
                }
            }

            ast::ExprKind::Match(target, arms) => {
                let target = self.lower_expr(*target)?;

                let mut ir_arms = Vec::new();
                let ty = ir::Type::infer();

                for arm in arms {
                    let pattern = self.lower_pattern(arm.pattern, target.ty.clone())?;
                    let expr = self.lower_expr(arm.expr)?;
                    self.unify(expr.ty.clone(), ty.clone(), expr.span);
                    ir_arms.push(ir::Arm { pattern, expr });
                }

                self.exhaust(&ir_arms, expr.span)?;

                let span = expr.span;
                let kind = ir::ExprKind::Match(Box::new(target), ir_arms);
                ir::Expr { kind, span, ty }
            }

            ast::ExprKind::Block(ast_exprs) => {
                let mut ir_exprs = Vec::new();
                let mut ty = ir::Type::unit();

                // save current scope length to restore later
                let old_scope_len = self.scope.len();

                for ast_expr in ast_exprs {
                    let expr = self.lower_expr(ast_expr)?;
                    ty = expr.ty.clone();
                    ir_exprs.push(expr);
                }

                // restore scope to the length before the block
                self.scope.truncate(old_scope_len);

                ir::Expr {
                    kind: ir::ExprKind::Block(ir_exprs),
                    span: expr.span,
                    ty,
                }
            }
        })
    }

    fn exhaust(&mut self, arms: &[ir::Arm], span: Span) -> Result<(), LowerError> {
        let matrix = Matrix::new(arms);
        let exhaustive = self.exhaust_impl(matrix);

        if !exhaustive {
            let diagnostic = Diagnostic::error("non-exhaustive patterns in match expression")
                .with_label(span, "found here");

            self.lowerer.emitter.emit(diagnostic);
            return Err(LowerError);
        }

        Ok(())
    }

    fn exhaust_impl(&mut self, matrix: Matrix) -> bool {
        let cons = match matrix.pattern() {
            Some(pattern) => match pattern.kind {
                ir::PatternKind::Bool(_) => vec![Cons::Bool(true), Cons::Bool(false)],
                ir::PatternKind::ListEmpty => vec![Cons::List(false), Cons::List(true)],
                ir::PatternKind::ListCons(_, _) => vec![Cons::List(false), Cons::List(true)],

                ir::PatternKind::Variant(ref ty, _, _) => {
                    let ir::Type::App(ir::App::Newtype(tid, _)) = ty else {
                        unreachable!();
                    };

                    let newtype = &self.ir.tcx[*tid];
                    let ir::NewtypeKind::Union(ref union) = newtype.kind else {
                        unreachable!();
                    };

                    let mut cons = Vec::new();

                    for variant in &union.variants {
                        cons.push(Cons::Variant(variant.name.clone(), variant.ty.is_some()));
                    }

                    cons
                }

                ir::PatternKind::Tuple(ref items) => vec![Cons::Tuple(items.len())],

                ir::PatternKind::Wildcard | ir::PatternKind::Binding(_) => {
                    unreachable!();
                }
            },
            None => vec![Cons::Wildcard],
        };

        for cons in cons {
            let matrix = match matrix.specialize(&cons) {
                Some(matrix) => matrix,
                None => return false,
            };

            if matrix.len() == 0 {
                continue;
            }

            if !self.exhaust_impl(matrix) {
                return false;
            }
        }

        true
    }
}

#[derive(Debug)]
struct MatrixRow {
    patterns: Vec<ir::Pattern>,
}

impl MatrixRow {
    fn new(arm: &ir::Arm) -> Self {
        Self {
            patterns: vec![arm.pattern.clone()],
        }
    }

    fn specialize(&self, cons: &Cons) -> Option<Self> {
        let pattern = &self.patterns[0];
        let mut patterns = cons.specialize(pattern)?;
        patterns.extend(self.patterns.iter().skip(1).cloned());
        Some(Self { patterns })
    }
}

#[derive(Debug)]
struct Matrix {
    rows: Vec<MatrixRow>,
}

impl Matrix {
    fn new(args: &[ir::Arm]) -> Self {
        let mut rows = Vec::new();

        for arm in args {
            rows.push(MatrixRow::new(arm));
        }

        Self { rows }
    }

    fn len(&self) -> usize {
        self.rows[0].patterns.len()
    }

    fn pattern(&self) -> Option<&ir::Pattern> {
        for row in self.rows.iter() {
            let pattern = &row.patterns[0];

            if !matches!(
                pattern.kind,
                ir::PatternKind::Wildcard | ir::PatternKind::Binding(_)
            ) {
                return Some(pattern);
            }
        }

        None
    }

    fn specialize(&self, cons: &Cons) -> Option<Self> {
        let mut rows = Vec::new();

        for row in &self.rows {
            if let Some(specialized_row) = row.specialize(cons) {
                rows.push(specialized_row);
            }
        }

        match rows.is_empty() {
            false => Some(Self { rows }),
            true => None,
        }
    }
}

#[derive(Debug)]
enum Cons {
    Bool(bool),
    List(bool),
    Tuple(usize),
    Variant(String, bool),
    Wildcard,
}

impl Cons {
    fn arity(&self) -> usize {
        match self {
            Cons::Bool(_) => 0,
            Cons::List(false) => 0,
            Cons::List(true) => 2,
            Cons::Tuple(len) => *len,
            Cons::Variant(_, true) => 1,
            Cons::Variant(_, false) => 0,
            Cons::Wildcard => 0,
        }
    }

    fn specialize(&self, pattern: &ir::Pattern) -> Option<Vec<ir::Pattern>> {
        match (self, &pattern.kind) {
            (Cons::Bool(true), ir::PatternKind::Bool(true)) => Some(Vec::new()),
            (Cons::Bool(false), ir::PatternKind::Bool(false)) => Some(Vec::new()),

            (Cons::Tuple(_), ir::PatternKind::Tuple(items)) => Some(items.clone()),

            (Cons::List(false), ir::PatternKind::ListEmpty) => Some(Vec::new()),

            (Cons::List(true), ir::PatternKind::ListCons(head, tail)) => {
                Some(vec![head.as_ref().clone(), tail.as_ref().clone()])
            }

            (Cons::Variant(c, _), ir::PatternKind::Variant(_, v, p)) if c == v => match p {
                Some(inner) => Some(vec![inner.as_ref().clone()]),
                None => Some(Vec::new()),
            },

            (Cons::Wildcard, _) => Some(Vec::new()),

            (cons, ir::PatternKind::Wildcard | ir::PatternKind::Binding(_)) => {
                let wildcard = ir::Pattern {
                    kind: ir::PatternKind::Wildcard,
                    span: pattern.span,
                };

                Some(vec![wildcard; cons.arity()])
            }

            (_, _) => None,
        }
    }
}

impl<'a> Deref for ExprLowerer<'_, 'a> {
    type Target = Lowerer<'a>;

    fn deref(&self) -> &Self::Target {
        self.lowerer
    }
}

impl DerefMut for ExprLowerer<'_, '_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.lowerer
    }
}
