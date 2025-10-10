use crate::{
    ast,
    diagnostic::Diagnostic,
    parse::{
        Parser, Token, parse_newlines, parse_path, pattern::parse_pattern, r#type::parse_type,
    },
};

fn is_expr(parser: &mut Parser<'_>) -> bool {
    matches!(
        parser.peek(0),
        Token::Let
            | Token::Integer
            | Token::String
            | Token::True
            | Token::False
            | Token::None
            | Token::Ident
            | Token::LParen
            | Token::LBrace
    )
}

pub fn parse_expr(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Let => parse_let_expr(parser),
        _ => parse_eq_expr(parser),
    }
}

fn parse_let_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::LetExpr);

    parser.expect(Token::Let);

    parse_pattern(parser);

    if parser.is(Token::Colon) {
        parser.expect(Token::Colon);
        parse_type(parser);
    }

    parser.expect(Token::Eq);

    parse_expr(parser);

    parser.close();
}

fn parse_eq_expr(parser: &mut Parser<'_>) {
    parse_binary(parser, parse_cmp_expr, &[Token::EqEq, Token::BangEq]);
}

fn parse_cmp_expr(parser: &mut Parser<'_>) {
    parse_binary(
        parser,
        parse_add_sub_expr,
        &[Token::LtEq, Token::GtEq, Token::Lt, Token::Gt],
    );
}

fn parse_add_sub_expr(parser: &mut Parser<'_>) {
    parse_binary(parser, parse_mul_div_mod_expr, &[Token::Plus, Token::Minus]);
}

fn parse_mul_div_mod_expr(parser: &mut Parser<'_>) {
    parse_binary(
        parser,
        parse_call_expr,
        &[Token::Star, Token::Slash, Token::Percent],
    );
}

fn parse_binary(parser: &mut Parser<'_>, parse_fn: impl Fn(&mut Parser<'_>), infixes: &[Token]) {
    parse_fn(parser);

    while infixes.contains(&parser.peek(0)) {
        parser.open_before(ast::Kind::BinaryExpr);
        parser.advance(1);
        parse_fn(parser);
        parser.close();
    }
}

fn parse_call_expr(parser: &mut Parser<'_>) {
    const BREAK: &[Token] = &[Token::RParen, Token::Type, Token::Eof];

    parse_term_expr(parser);

    if parser.is(Token::LParen) {
        parser.open_before(ast::Kind::CallExpr);
        parser.expect(Token::LParen);

        while !BREAK.contains(&parser.peek(0)) {
            parse_expr(parser);

            if !parser.is(Token::RParen) {
                parser.expect(Token::Comma);
            }
        }

        parser.expect(Token::RParen);
        parser.close();
    }
}

fn parse_term_expr(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Integer => parse_int_expr(parser),
        Token::String => parse_str_expr(parser),
        Token::True => parse_true_expr(parser),
        Token::False => parse_false_expr(parser),
        Token::None => parse_none_expr(parser),
        Token::Ident => parse_path_expr(parser),
        Token::LParen => parse_paren_expr(parser),
        Token::LBrace => parse_block_or_record_expr(parser),

        token => {
            let diagnostic = Diagnostic::error(format!(
                "expected expression found `{token}`", //
            ))
            .label(parser.span(0), "here");

            parser.error(diagnostic);
        }
    }
}

fn parse_int_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::IntExpr);
    parser.expect(Token::Integer);
    parser.close();
}

fn parse_str_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::StrExpr);
    parser.expect(Token::String);
    parser.close();
}

fn parse_true_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::TrueExpr);
    parser.expect(Token::True);
    parser.close();
}

fn parse_false_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::FalseExpr);
    parser.expect(Token::False);
    parser.close();
}

fn parse_none_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::NoneExpr);
    parser.expect(Token::None);
    parser.close();
}

fn parse_path_expr(parser: &mut Parser<'_>) {
    parse_path(parser);

    if is_expr(parser) {
        parser.open_before(ast::Kind::PromoteExpr);
        parse_expr(parser);
        parser.close();
    } else {
        parser.open_before(ast::Kind::PathExpr);
        parser.close();
    }
}

fn parse_paren_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::ParenExpr);
    parser.expect(Token::LParen);
    parse_expr(parser);
    parser.expect(Token::RParen);
    parser.close();
}

fn parse_block_or_record_expr(parser: &mut Parser<'_>) {
    if is_record_expr(parser) {
        parse_record_expr(parser);
    } else {
        parse_block_expr(parser);
    }
}

pub fn parse_block_expr(parser: &mut Parser<'_>) {
    const BREAK: &[Token] = &[Token::RBrace, Token::Type, Token::Eof];

    parser.open(ast::Kind::BlockExpr);
    parser.expect(Token::LBrace);

    parse_newlines(parser);

    while !BREAK.contains(&parser.peek(0)) {
        parse_expr(parser);

        if !parser.is(Token::RBrace) {
            parser.expect(Token::Newline);
        }

        parse_newlines(parser);
    }

    parser.expect(Token::RBrace);
    parser.close();
}

fn is_record_expr(parser: &mut Parser<'_>) -> bool {
    if !parser.is(Token::LBrace) {
        return false;
    }

    let mut i = 1;

    while matches!(parser.peek(i), Token::Newline) {
        i += 1;
    }

    matches!(
        (parser.peek(i), parser.peek(i + 1)),
        (Token::Ident, Token::Colon),
    )
}

fn parse_record_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::RecordExpr);
    parser.expect(Token::LBrace);

    parse_newlines(parser);

    while parser.is(Token::Ident) {
        parser.open(ast::Kind::Field);

        parser.expect(Token::Ident);
        parser.expect(Token::Colon);
        parse_expr(parser);

        parser.close();

        if parser.is(Token::Comma) {
            parser.expect(Token::Comma);
            parse_newlines(parser);
        } else if parser.is(Token::Newline) {
            parser.expect(Token::Newline);
            parse_newlines(parser);
        } else {
            break;
        }
    }

    parser.expect(Token::RBrace);
    parser.close();
}

#[cfg(test)]
mod tests {
    use crate::{ast, parse::*};

    #[test]
    fn int() {
        test_parser! {
            parse_expr : "0" =>
            ast::Kind::IntExpr {
                Token::Integer,
            },
        }
    }

    #[test]
    fn bool() {
        test_parser! {
            parse_expr : "true" =>
            ast::Kind::TrueExpr {
                Token::True,
            },
        }

        test_parser! {
            parse_expr : "false" =>
            ast::Kind::FalseExpr {
                Token::False,
            },
        }
    }

    #[test]
    fn path() {
        test_parser! {
            parse_expr : "a::b" =>
            ast::Kind::PathExpr {
                ast::Kind::Path {
                    Token::Ident,
                    Token::ColonColon,
                    Token::Ident,
                },
            },
        }
    }

    #[test]
    fn paren() {
        test_parser! {
            parse_expr : "(0)" =>
            ast::Kind::ParenExpr {
                Token::LParen,
                ast::Kind::IntExpr {
                    Token::Integer,
                },
                Token::RParen,
            },
        }
    }

    #[test]
    fn block() {
        test_parser! {
            parse_expr : "{}" =>
            ast::Kind::BlockExpr {
                Token::LBrace,
                Token::RBrace,
            },
        }

        test_parser! {
            parse_expr : "{ 0 }" =>
            ast::Kind::BlockExpr {
                Token::LBrace,
                ast::Kind::IntExpr {
                    Token::Integer,
                },
                Token::RBrace,
            },
        }

        test_parser! {
            parse_expr : "{
                0
                true
            }" =>
            ast::Kind::BlockExpr {
                Token::LBrace,
                Token::Newline,
                ast::Kind::IntExpr {
                    Token::Integer,
                },
                Token::Newline,
                ast::Kind::TrueExpr {
                    Token::True,
                },
                Token::Newline,
                Token::RBrace,
            },
        }
    }
}
