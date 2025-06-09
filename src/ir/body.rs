use std::marker::PhantomData;

use super::{Expr, Pattern, arena::impl_arena};

#[derive(Clone, Debug, PartialEq)]
pub struct Body<T> {
    pub name: String,
    pub locals: Locals<T>,
    pub inputs: Vec<Pattern<T>>,
    pub expr: Option<Expr<T>>,
    pub ty: T,
}

#[derive(Clone, Debug, PartialEq, Hash)]
pub struct Local<T> {
    pub name: String,
    pub ty: T,
}

impl_arena!(Locals, Local<T>, Lid);
impl_arena!(Bodies, Body<T>, Bid);
