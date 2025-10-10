use std::ops::{Index, IndexMut};

use crate::ir::{Alias, Body, Module, Newtype};

/// One compilation unit.
#[derive(Clone, Debug)]
pub struct Unit {
    modules:  Vec<Module>,
    bodies:   Vec<Body>,
    aliases:  Vec<Alias>,
    newtypes: Vec<Newtype>,
}

impl Default for Unit {
    fn default() -> Self {
        Self::new()
    }
}

impl Unit {
    pub fn new() -> Self {
        Self {
            modules:  vec![Module::default()],
            bodies:   Vec::new(),
            aliases:  Vec::new(),
            newtypes: Vec::new(),
        }
    }

    pub fn add_module(&mut self) -> ModuleId {
        let index = self.modules.len();
        self.modules.push(Module::default());
        ModuleId { index }
    }

    pub fn add_body(&mut self, body: Body) -> BodyId {
        let index = self.bodies.len();
        self.bodies.push(body);
        BodyId { index }
    }

    pub fn add_alias(&mut self, alias: Alias) -> AliasId {
        let index = self.aliases.len();
        self.aliases.push(alias);
        AliasId { index }
    }

    pub fn add_newtype(&mut self, newtype: Newtype) -> NewtypeId {
        let index = self.newtypes.len();
        self.newtypes.push(newtype);
        NewtypeId { index }
    }

    pub fn find_module<I>(&self, mut current: ModuleId, segments: I) -> Result<ModuleId, I::Item>
    where
        I: IntoIterator,
        I::Item: AsRef<str>,
        I::IntoIter: ExactSizeIterator,
    {
        let segments = segments.into_iter();

        let len = segments.len() - 1;
        for segment in segments.take(len) {
            let Some(&module_id) = self[current].modules.get(segment.as_ref()) else {
                return Err(segment);
            };

            current = module_id;
        }

        Ok(current)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ModuleId {
    index: usize,
}

impl ModuleId {
    pub const ROOT: Self = Self { index: 0 };
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BodyId {
    index: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct NewtypeId {
    index: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct AliasId {
    index: usize,
}

impl Index<ModuleId> for Unit {
    type Output = Module;

    fn index(&self, id: ModuleId) -> &Self::Output {
        &self.modules[id.index]
    }
}

impl Index<BodyId> for Unit {
    type Output = Body;

    fn index(&self, id: BodyId) -> &Self::Output {
        &self.bodies[id.index]
    }
}

impl Index<AliasId> for Unit {
    type Output = Alias;

    fn index(&self, id: AliasId) -> &Self::Output {
        &self.aliases[id.index]
    }
}

impl Index<NewtypeId> for Unit {
    type Output = Newtype;

    fn index(&self, id: NewtypeId) -> &Self::Output {
        &self.newtypes[id.index]
    }
}

impl IndexMut<ModuleId> for Unit {
    fn index_mut(&mut self, id: ModuleId) -> &mut Self::Output {
        &mut self.modules[id.index]
    }
}

impl IndexMut<BodyId> for Unit {
    fn index_mut(&mut self, id: BodyId) -> &mut Self::Output {
        &mut self.bodies[id.index]
    }
}

impl IndexMut<AliasId> for Unit {
    fn index_mut(&mut self, id: AliasId) -> &mut Self::Output {
        &mut self.aliases[id.index]
    }
}

impl IndexMut<NewtypeId> for Unit {
    fn index_mut(&mut self, id: NewtypeId) -> &mut Self::Output {
        &mut self.newtypes[id.index]
    }
}
