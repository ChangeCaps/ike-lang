use std::iter::Peekable;

use crate::parse::Token;

pub struct Parser<I>
where
    I: Iterator<Item = (Token, usize)>,
{
    tokens: Peekable<I>,
}
