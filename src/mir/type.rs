#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Type {
    Num,
    Str,
    Bool,
    Never,
    List(Box<Type>),
    Fn(Vec<Type>, Box<Type>),
    Record(Vec<Type>),
    Union(Vec<Type>),
}
