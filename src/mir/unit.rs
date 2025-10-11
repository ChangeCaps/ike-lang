use std::ops::Index;

use crate::mir::{Body, Type};

#[derive(Clone, Debug, Default)]
pub struct Unit {
    bodies: Vec<Option<Body>>,
    types:  Vec<Option<Type>>,
}

impl Unit {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reserve_body(&mut self) -> BodyId {
        let index = self.bodies.len();
        self.bodies.push(None);
        BodyId { index }
    }

    pub fn reserve_type(&mut self) -> TypeId {
        let index = self.types.len();
        self.types.push(None);
        TypeId { index }
    }

    pub fn insert_body(&mut self, body_id: BodyId, body: Body) {
        self.bodies[body_id.index] = Some(body);
    }

    pub fn insert_type(&mut self, type_id: TypeId, ty: Type) {
        self.types[type_id.index] = Some(ty);
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BodyId {
    index: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TypeId {
    index: usize,
}

impl Index<BodyId> for Unit {
    type Output = Body;

    fn index(&self, id: BodyId) -> &Self::Output {
        self.bodies[id.index].as_ref().unwrap()
    }
}

impl Index<TypeId> for Unit {
    type Output = Type;

    fn index(&self, id: TypeId) -> &Self::Output {
        self.types[id.index].as_ref().unwrap()
    }
}
