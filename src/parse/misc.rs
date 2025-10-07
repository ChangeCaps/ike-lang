use crate::{
    ast,
    parse::{Parser, Token, parse_type},
};

pub fn parse_newlines(parser: &mut Parser<'_>) {
    while parser.is(Token::Newline) {
        parser.expect(Token::Newline);
    }
}

pub fn parse_path(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Path);

    parser.expect(Token::Ident);

    while parser.is(Token::ColonColon) {
        parser.expect(Token::ColonColon);
        parser.expect(Token::Ident);
    }

    parser.close();
}

pub fn parse_param(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Param);

    parser.expect(Token::Ident);
    parser.expect(Token::Colon);
    parse_type(parser);

    parser.close();
}

pub fn parse_params(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Params);

    parser.expect(Token::LParen);

    while parser.is(Token::Ident) {
        parse_param(parser);

        if !parser.is(Token::Comma) {
            break;
        }

        parser.expect(Token::Comma);
    }

    parser.expect(Token::RParen);

    parser.close();
}
