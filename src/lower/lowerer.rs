use std::mem;

use crate::{
    ast,
    diagnostic::{self, Diagnostic},
    ir::{
        Alias, AliasId, Body, BodyId, Expr, Local, ModuleId, Newtype, NewtypeId, Parameter,
        Pattern, PatternKind, Type, Unit,
    },
    lower::{body::BodyLowerer, r#type::TypeLowerer},
};

pub struct AliasDesc {
    module_id: ModuleId,
    alias_id:  AliasId,
    ast:       ast::Node,
}

pub struct NewtypeDesc {
    module_id:  ModuleId,
    newtype_id: NewtypeId,
    ast:        ast::Node,
}

pub struct FnDesc {
    module_id: ModuleId,
    body_id:   BodyId,
    ast:       ast::Node,
}

pub struct Lowerer<'a> {
    pub(super) emitter: &'a mut dyn diagnostic::Emitter,
    pub(super) unit:    Unit,

    pub(super) fns:      Vec<FnDesc>,
    pub(super) aliases:  Vec<AliasDesc>,
    pub(super) newtypes: Vec<NewtypeDesc>,
}

impl<'a> Lowerer<'a> {
    pub fn new(emitter: &'a mut dyn diagnostic::Emitter) -> Self {
        Self {
            emitter,
            unit: Unit::new(),

            fns: Vec::new(),
            aliases: Vec::new(),
            newtypes: Vec::new(),
        }
    }

    pub fn finish(mut self) -> Unit {
        self.lower_types();

        self.unit
    }

    pub fn add_file(&mut self, path: &[impl AsRef<str>], ast: &ast::Node) {
        assert_eq!(ast.kind, ast::Kind::File);

        let module_id = self.add_module(path);

        for node in ast.nodes() {
            match node.kind {
                ast::Kind::AliasItem => self.add_alias(module_id, node),
                ast::Kind::TypeItem => self.add_type(module_id, node),
                ast::Kind::FnItem => self.add_fn(module_id, node),

                // if the node is an error, no useful information is obtainable
                ast::Kind::Error => {}

                // any kind other than the above should be impossible
                _ => unreachable!(),
            }
        }
    }

    fn add_module(&mut self, path: &[impl AsRef<str>]) -> ModuleId {
        let mut id = ModuleId::ROOT;

        for segment in path {
            let segment = segment.as_ref();

            match self.unit[id].modules.get(segment) {
                Some(new_id) => id = *new_id,
                None => {
                    let new_id = self.unit.add_module();
                    self.unit[id].modules.insert(segment.to_owned(), new_id);
                    id = new_id;
                }
            }
        }

        id
    }

    fn add_alias(&mut self, module_id: ModuleId, ast: &ast::Node) {
        assert_eq!(ast.kind, ast::Kind::AliasItem);

        let Some(name) = ast.string(1) else {
            return;
        };

        if self.unit[module_id].has_type(name) {
            let diagnostic = Diagnostic::error(format!(
                "duplicate definition of type `{name}`" //
            ))
            .label(ast.span(1), "here");

            self.emit(diagnostic);
        }

        let alias = Alias {
            generics: Vec::new(),
            ty:       Type::Unknown,
        };

        let alias_id = self.unit.add_alias(alias);

        self.unit[module_id].aliases.insert(name.into(), alias_id);

        let desc = AliasDesc {
            module_id,
            alias_id,
            ast: ast.clone(),
        };

        self.aliases.push(desc);
    }

    fn add_type(&mut self, module_id: ModuleId, ast: &ast::Node) {
        assert_eq!(ast.kind, ast::Kind::TypeItem);

        let Some(name) = ast.string(1) else {
            return;
        };

        if self.unit[module_id].has_type(name) {
            let diagnostic = Diagnostic::error(format!(
                "duplicate definition of type `{name}`" //
            ))
            .label(ast.span(1), "here");

            self.emit(diagnostic);
        }

        let newtype = Newtype {
            generics: Vec::new(),
            ty:       Type::Unknown,
        };

        let newtype_id = self.unit.add_newtype(newtype);

        (self.unit[module_id].newtypes).insert(name.into(), newtype_id);

        let desc = NewtypeDesc {
            module_id,
            newtype_id,
            ast: ast.clone(),
        };

        self.newtypes.push(desc);
    }

    fn add_fn(&mut self, module_id: ModuleId, ast: &ast::Node) {
        assert_eq!(ast.kind, ast::Kind::FnItem);

        let Some(name) = ast.string(1) else {
            return;
        };

        if self.unit[module_id].has_body(name) {
            let diagnostic = Diagnostic::error(format!(
                "duplicate definition of function `{name}`" //
            ))
            .label(ast.span(1), "here");

            self.emit(diagnostic);
        }

        let body = Body {
            name:   Some(name.into()),
            locals: Vec::new(),
            params: Vec::new(),
            ty:     Type::Unknown,
            expr:   None,
        };

        // generate the id of the body
        let body_id = self.unit.add_body(body);

        // register the body in the correct module
        self.unit[module_id].bodies.insert(name.into(), body_id);

        let desc = FnDesc {
            module_id,
            body_id,
            ast: ast.clone(),
        };

        self.fns.push(desc);
    }

    fn emit(&mut self, diagnostic: Diagnostic) {
        self.emitter.emit(diagnostic);
    }

    fn lower_types(&mut self) {
        for desc in mem::take(&mut self.aliases) {
            let type_lowerer = TypeLowerer::new(self, desc.module_id);

            let ty = type_lowerer.lower_type(desc.ast.node(3));
            self.unit[desc.alias_id].ty = ty;
        }

        for desc in mem::take(&mut self.newtypes) {
            let type_lowerer = TypeLowerer::new(self, desc.module_id);

            let ty = type_lowerer.lower_type(desc.ast.node(3));
            self.unit[desc.newtype_id].ty = ty;
        }

        let fns = mem::take(&mut self.fns);
        for desc in &fns {
            let mut lowerer = BodyLowerer::new(self, desc.module_id, desc.body_id);

            for param in desc.ast.node(2).nodes() {
                let ty = lowerer.lower_type(param.node(2));

                let param = Parameter {
                    pattern: Pattern {
                        kind: PatternKind::Wildcard,
                        span: param.span,
                    },
                    ty,
                };

                lowerer.body_mut().params.push(param);
            }

            match desc.ast.semantic_children().count() {
                4 => {
                    lowerer.body_mut().ty = Type::None;
                }

                6 => {
                    let ty = lowerer.lower_type(desc.ast.node(4));
                    lowerer.body_mut().ty = ty;
                }

                _ => unreachable!(),
            }
        }
        self.fns = fns;
    }

    fn lower_fns(&mut self) {}
}
