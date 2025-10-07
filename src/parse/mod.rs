mod expr;
mod item;
mod misc;
mod parser;
mod pattern;
mod stream;
mod token;
mod r#type;

use expr::*;
use item::*;
use misc::*;
use r#type::*;

pub use parser::*;
pub use stream::*;
pub use token::*;

use crate::{
    ast,
    diagnostic::{self, SourceId},
};

pub fn parse_file(
    emitter: &mut dyn diagnostic::Emitter,
    input: &str,
    source: SourceId,
) -> ast::Node {
    let mut parser = Parser::new(emitter, input, source);
    parser.open(ast::Kind::File);

    parse_newlines(&mut parser);

    while !parser.is(Token::Eof) {
        parse_item(&mut parser);
        parse_newlines(&mut parser);
    }

    parser.finish()
}
