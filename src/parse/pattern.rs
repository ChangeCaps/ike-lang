use crate::{
    ast,
    diagnostic::Diagnostic,
    parse::{Parser, Token},
};

pub fn parse_pattern(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Ident => parse_binding_pattern(parser),

        token => {
            let diagnostic = Diagnostic::error(format!(
                "expected pattern found `{token}`", //
            ))
            .label(parser.span(0), "here");

            parser.error(diagnostic);
        }
    }
}

fn parse_binding_pattern(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::BindingPattern);
    parser.expect(Token::Ident);
    parser.close();
}
