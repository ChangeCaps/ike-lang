use crate::mir::{BlockId, Value};

#[derive(Clone, Debug)]
pub enum Terminator {
    Return(Value),
    Jump(BlockId),
}
