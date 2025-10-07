use std::ops::{Deref, DerefMut};

use crate::{
    ast,
    diagnostic::Diagnostic,
    ir::{GenericParameter, ModuleId, Type},
    lower::Lowerer,
};

pub struct TypeLowerer<'a, 'b> {
    lowerer:  &'a mut Lowerer<'b>,
    generics: &'a [GenericParameter],
    module:   ModuleId,
}

impl<'a, 'b> TypeLowerer<'a, 'b> {
    pub fn new(
        lowerer: &'a mut Lowerer<'b>,
        generics: &'a [GenericParameter],
        module: ModuleId,
    ) -> Self {
        Self {
            lowerer,
            generics,
            module,
        }
    }

    pub fn lower_type(&mut self, ast: &ast::Node) -> Type {
        let mut ty = match ast.kind {
            ast::Kind::NatType => Type::Nat,
            ast::Kind::IntType => Type::Int,
            ast::Kind::NumType => Type::Num,
            ast::Kind::StrType => Type::Str,
            ast::Kind::BoolType => Type::Bool,
            ast::Kind::NoneType => Type::None,
            ast::Kind::NeverType => Type::Never,

            ast::Kind::UnionType => {
                let variants = ast.nodes().map(|n| self.lower_type(n)).collect();

                Type::Union { variants }
            }

            ast::Kind::ParenType => self.lower_type(ast.node(1)),

            ast::Kind::GenericType => match ast.string(1) {
                Some(name) => {
                    match (self.generics.iter()).find(|p| p.name.as_deref() == Some(name)) {
                        Some(p) => Type::Generic { generic: p.generic },
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
        };

        self.unit.normalize_type(&mut ty);

        ty
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
