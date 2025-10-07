use std::ops::Deref;

use crate::{
    ast,
    ir::{ModuleId, Type},
    lower::Lowerer,
};

pub struct TypeLowerer<'a, 'b> {
    lowerer: &'a Lowerer<'b>,
    module:  ModuleId,
}

impl<'a, 'b> TypeLowerer<'a, 'b> {
    pub fn new(lowerer: &'a Lowerer<'b>, module: ModuleId) -> Self {
        Self { lowerer, module }
    }

    pub fn lower_type(&self, ast: &ast::Node) -> Type {
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
