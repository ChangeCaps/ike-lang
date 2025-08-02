use std::ops::{Index, IndexMut};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Tid {
    index: u64,
}

impl Tid {
    pub const fn index(self) -> u64 {
        self.index
    }
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

    pub fn iter(&self) -> impl Iterator<Item = (Tid, &Newtype)> {
        self.types
            .iter()
            .enumerate()
            .map(|(i, t)| (Tid { index: i as u64 }, t))
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
    Alias(Type),
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
