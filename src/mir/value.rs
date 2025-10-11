use crate::mir::{Operand, Place};

#[derive(Clone, Debug)]
pub enum Value {
    Use(Operand),
    Binary(BinOp, Operand, Operand),
    Record(Vec<Operand>),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Lt,
    Gt,
    Le,
    Ge,
}

impl From<Operand> for Value {
    fn from(value: Operand) -> Self {
        Self::Use(value)
    }
}

impl From<Place> for Value {
    fn from(value: Place) -> Self {
        Self::Use(Operand::Copy(value))
    }
}
