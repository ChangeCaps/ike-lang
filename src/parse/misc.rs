use crate::{
    ast,
    parse::{Parser, Token, parse_type, pattern::parse_pattern, r#type::is_type},
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

pub fn parse_parameter(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Param);

    parse_pattern(parser);
    parser.expect(Token::Colon);
    parse_type(parser);

    parser.close();
}

pub fn parse_parameters(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Params);

    parser.expect(Token::LParen);

    while parser.is(Token::Ident) {
        parse_parameter(parser);

        if !parser.is(Token::Comma) {
            break;
        }

        parser.expect(Token::Comma);
    }

    parser.expect(Token::RParen);

    parser.close();
}

pub fn parse_generics(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Generics);

    if parser.is(Token::Lt) {
        parser.expect(Token::Lt);

        while is_type(parser) {
            parse_type(parser);

            if !parser.is(Token::Comma) {
                break;
            }

            parser.expect(Token::Comma);
        }

        parser.expect(Token::Gt);
    }

    parser.close();
}
