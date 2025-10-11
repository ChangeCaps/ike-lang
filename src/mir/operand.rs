use crate::mir::Place;

#[derive(Clone, Debug)]
pub enum Operand {
    Copy(Place),
    Constant(Constant),
}

impl Operand {
    pub const NONE: Self = Self::Constant(Constant::None);
}

#[derive(Clone, Debug)]
pub enum Constant {
    None,
    Num(f64),
    Bool(bool),
}
