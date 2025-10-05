use crate::parse::{Parser, Token};

pub fn parse_path(parser: &mut Parser<'_>) {
    parser.expect(Token::Ident);
}
