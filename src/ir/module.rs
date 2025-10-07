use std::collections::HashMap;

use crate::ir::{AliasId, BodyId, ModuleId, NewtypeId};

#[derive(Clone, Debug, Default)]
pub struct Module {
    pub modules:  HashMap<String, ModuleId>,
    pub bodies:   HashMap<String, BodyId>,
    pub aliases:  HashMap<String, AliasId>,
    pub newtypes: HashMap<String, NewtypeId>,
}

impl Module {
    pub fn has_body(&self, name: impl AsRef<str>) -> bool {
        self.bodies.contains_key(name.as_ref())
    }

    pub fn has_type(&self, name: impl AsRef<str>) -> bool {
        self.aliases.contains_key(name.as_ref()) || self.newtypes.contains_key(name.as_ref())
    }
}
