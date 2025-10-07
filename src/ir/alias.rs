use crate::ir::{Generic, Type};

#[derive(Clone, Debug)]
pub struct Alias {
    pub generics: Vec<Generic>,
    pub ty:       Type,
}
