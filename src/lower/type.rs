use std::ops::{Deref, DerefMut};

use crate::{
    ast,
    diagnostic::Diagnostic,
    ir::{GenericParameter, ModuleId, Type, TypeField},
    lower::Lowerer,
};

pub struct TypeLowerer<'a, 'b> {
    lowerer:   &'a mut Lowerer<'b>,
    generics:  &'a [GenericParameter],
    module_id: ModuleId,
}

impl<'a, 'b> TypeLowerer<'a, 'b> {
    pub fn new(
        lowerer: &'a mut Lowerer<'b>,
        generics: &'a [GenericParameter],
        module_id: ModuleId,
    ) -> Self {
        Self {
            lowerer,
            generics,
            module_id,
        }
    }

    pub fn lower_type(&mut self, ast: &ast::Node) -> Type {
        match ast.kind {
            ast::Kind::NatType => Type::Nat,
            ast::Kind::IntType => Type::Int,
            ast::Kind::NumType => Type::Num,
            ast::Kind::StrType => Type::Str,
            ast::Kind::BoolType => Type::Bool,
            ast::Kind::NoneType => Type::None,
            ast::Kind::NeverType => Type::Never,

            ast::Kind::PathType => {
                let segments = ast.node(0).idents().collect::<Vec<_>>();

                let module_id = match self.unit.find_module(self.module_id, &segments) {
                    Ok(module_id) => module_id,
                    Err(segment) => {
                        let diagnostic = Diagnostic::error(format!("module `{segment}` not found"))
                            .label(ast.span, "in path found here");

                        self.error(diagnostic);

                        return Type::Error;
                    }
                };

                let &name = segments.last().unwrap();

                let mut generics = Vec::new();

                for node in ast.nodes_of(ast::Kind::Generics).next().unwrap().nodes() {
                    let ty = self.lower_type(node);
                    generics.push(ty);
                }

                if let Some(&alias_id) = self.unit[module_id].aliases.get(name) {
                    let alias = &self.unit[alias_id];

                    if generics.len() != alias.generics.len() {
                        let diagnostic = Diagnostic::error(format!(
                            "wrong number of generics, expected `{expected}`, found `{found}`",
                            expected = alias.generics.len(),
                            found = generics.len(),
                        ))
                        .label(ast.span, "here");

                        self.error(diagnostic);

                        return Type::Error;
                    }

                    return Type::Alias { alias_id, generics };
                }

                if let Some(&newtype_id) = self.unit[module_id].newtypes.get(name) {
                    let newtype = &self.unit[newtype_id];

                    if generics.len() != newtype.generics.len() {
                        let diagnostic = Diagnostic::error(format!(
                            "wrong number of generics, expected `{expected}`, found `{found}`",
                            expected = newtype.generics.len(),
                            found = generics.len(),
                        ))
                        .label(ast.span, "here");

                        self.error(diagnostic);

                        return Type::Error;
                    }

                    return Type::Newtype {
                        newtype_id,
                        generics,
                    };
                }

                let diagnostic = Diagnostic::error(format!("item `{name}` not found"))
                    .label(ast.span, "in path found here");

                self.error(diagnostic);

                Type::Error
            }

            ast::Kind::RecordType => {
                let mut fields = Vec::new();

                for field in ast.nodes_of(ast::Kind::Field) {
                    let Some(name) = field.string(0) else {
                        continue;
                    };

                    let ty = self.lower_type(field.node(2));

                    let field = TypeField {
                        name: name.into(),
                        ty,
                    };

                    fields.push(field);
                }

                Type::Record(fields)
            }

            ast::Kind::UnionType => {
                let variants = ast.nodes().map(|n| self.lower_type(n)).collect();

                Type::Union(variants)
            }

            ast::Kind::ParenType => self.lower_type(ast.node(1)),

            ast::Kind::GenericType => match ast.string(1) {
                Some(name) => {
                    match (self.generics.iter()).find(|p| p.name.as_deref() == Some(name)) {
                        Some(p) => Type::Generic(p.generic),
                        None => {
                            let diagnostic =
                                Diagnostic::error(format!("generic type `'{name}` not found"))
                                    .label(ast.span, "here");

                            self.error(diagnostic);

                            Type::Error
                        }
                    }
                }

                None => Type::Error,
            },

            ast::Kind::Error => Type::Error,

            _ => unreachable!("{:?}", ast.kind),
        }
    }
}

impl<'a> Deref for TypeLowerer<'_, 'a> {
    type Target = Lowerer<'a>;

    fn deref(&self) -> &Self::Target {
        self.lowerer
    }
}

impl DerefMut for TypeLowerer<'_, '_> {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.lowerer
    }
}
