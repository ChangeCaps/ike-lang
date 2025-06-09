use std::ops::{Index, IndexMut};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Tid {
    index: u64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Types {
    types: Vec<Newtype>,
}

impl Types {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn push_newtype(&mut self, newtype: Newtype) -> Tid {
        let index = self.types.len() as u64;
        self.types.push(newtype);
        Tid { index }
    }
}

impl Index<Tid> for Types {
    type Output = Newtype;

    fn index(&self, index: Tid) -> &Self::Output {
        &self.types[index.index as usize]
    }
}

impl IndexMut<Tid> for Types {
    fn index_mut(&mut self, index: Tid) -> &mut Self::Output {
        &mut self.types[index.index as usize]
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Type {
    Int,
    Str,
    Bool,
    Unit,
    List(Box<Type>),
    Tuple(Vec<Type>),
    Newtype(Tid, Vec<Type>),
    Function(Box<Type>, Box<Type>),
}

#[derive(Clone, Debug, PartialEq)]
pub enum Newtype {
    Record(Record),
    Union(Union),
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Record {
    pub fields: Vec<Field>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub name: String,
    pub ty: Type,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Union {
    pub variants: Vec<Variant>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Variant {
    pub name: String,
    pub ty: Option<Type>,
}
