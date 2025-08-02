mod context;
mod r#type;

use std::{
    collections::HashMap,
    ops::{Index, IndexMut},
};

pub use context::*;
pub use r#type::*;

pub type Expr = super::Expr<Type>;
pub type ExprKind = super::ExprKind<Type>;
pub type Arm = super::Arm<Type>;
pub type BinOp = super::BinOp;
pub type Pattern = super::Pattern<Type>;
pub type PatternKind = super::PatternKind<Type>;

pub type Local = super::Local<Type>;
pub type Locals = super::Locals<Type>;
pub type Lid = super::Lid<Type>;

pub type Body = super::Body<Type>;
pub type Bodies = super::Bodies<Type>;
pub type Bid = super::Bid<Type>;

#[derive(Clone, Debug)]
pub struct Program {
    pub modules: Vec<Module>,
    pub bodies: Bodies,
    pub tcx: TypeContext,
    pub root: Mid,
}

impl Default for Program {
    fn default() -> Self {
        Program::new()
    }
}

impl Program {
    pub fn new() -> Self {
        Program {
            modules: vec![Module::default()],
            bodies: Bodies::default(),
            tcx: TypeContext::default(),
            root: Mid { index: 0 },
        }
    }

    pub fn push_module(&mut self, module: Module) -> Mid {
        let index = self.modules.len() as u64;
        self.modules.push(module);
        Mid { index }
    }

    pub fn get_module<'a>(
        &self,
        mut current: Mid,
        path: impl Iterator<Item = &'a str>,
    ) -> Option<Mid> {
        for segment in path {
            let submodule = self.modules[current.index as usize].modules.get(segment)?;
            current = *submodule;
        }

        Some(current)
    }
}

impl Index<Mid> for Program {
    type Output = Module;

    fn index(&self, index: Mid) -> &Self::Output {
        &self.modules[index.index as usize]
    }
}

impl IndexMut<Mid> for Program {
    fn index_mut(&mut self, index: Mid) -> &mut Self::Output {
        &mut self.modules[index.index as usize]
    }
}

impl Index<Bid> for Program {
    type Output = Body;

    fn index(&self, index: Bid) -> &Self::Output {
        &self.bodies[index]
    }
}

impl IndexMut<Bid> for Program {
    fn index_mut(&mut self, index: Bid) -> &mut Self::Output {
        &mut self.bodies[index]
    }
}

#[derive(Clone, Debug, PartialEq, Default)]
pub struct Module {
    pub modules: HashMap<String, Mid>,
    pub bodies: HashMap<String, Bid>,
    pub newtypes: HashMap<String, Tid>,
    pub variants: HashMap<String, (Tid, String)>,
    pub imports: HashMap<String, Vec<String>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Mid {
    index: u64,
}

impl Mid {
    pub fn index(&self) -> u64 {
        self.index
    }
}
