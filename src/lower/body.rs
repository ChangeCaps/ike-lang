use std::ops::{Deref, DerefMut};

use crate::{
    ast,
    ir::{Body, BodyId, ModuleId, Type},
    lower::{Lowerer, r#type::TypeLowerer},
};

pub struct BodyLowerer<'a, 'b> {
    lowerer:   &'a mut Lowerer<'b>,
    module_id: ModuleId,
    body_id:   BodyId,
}

impl<'a, 'b> BodyLowerer<'a, 'b> {
    pub fn new(lowerer: &'a mut Lowerer<'b>, module_id: ModuleId, body_id: BodyId) -> Self {
        Self {
            lowerer,
            module_id,
            body_id,
        }
    }

    pub fn body(&self) -> &Body {
        &self.lowerer.unit[self.body_id]
    }

    pub fn body_mut(&mut self) -> &mut Body {
        &mut self.lowerer.unit[self.body_id]
    }

    pub fn lower_type(&self, ast: &ast::Node) -> Type {
        TypeLowerer::new(self, self.module_id).lower_type(ast)
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
