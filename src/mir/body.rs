use std::ops::{Index, IndexMut};

use crate::mir::{Statement, Terminator, Type};

#[derive(Clone, Debug)]
pub struct Body {
    pub name:      Option<String>,
    pub arguments: Vec<Type>,
    pub locals:    Vec<Type>,
    pub blocks:    Vec<Block>,
    pub output:    Type,
}

#[derive(Clone, Debug)]
pub struct Block {
    pub statements: Vec<Statement>,
    pub terminator: Terminator,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BlockId {
    pub(crate) index: usize,
}

impl Index<BlockId> for Body {
    type Output = Block;

    fn index(&self, id: BlockId) -> &Self::Output {
        &self.blocks[id.index]
    }
}

impl IndexMut<BlockId> for Body {
    fn index_mut(&mut self, id: BlockId) -> &mut Self::Output {
        &mut self.blocks[id.index]
    }
}
