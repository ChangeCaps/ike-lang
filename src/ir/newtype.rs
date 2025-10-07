use crate::ir::{Generic, Type};

#[derive(Clone, Debug)]
pub struct Newtype {
    pub generics: Vec<Generic>,
    pub ty:       Type,
}
