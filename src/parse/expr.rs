use crate::{
    ast,
    diagnostic::Diagnostic,
    parse::{Parser, Token, parse_newlines, parse_path},
};

pub fn parse_expr(parser: &mut Parser<'_>) {
    parse_term_expr(parser);
}

fn parse_term_expr(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Integer => parse_int_expr(parser),
        Token::String => parse_str_expr(parser),
        Token::True => parse_true_expr(parser),
        Token::False => parse_false_expr(parser),
        Token::Ident => parse_path_expr(parser),
        Token::LParen => parse_paren_expr(parser),
        Token::LBrace => parse_block_expr(parser),

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

fn parse_path_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::PathExpr);
    parse_path(parser);
    parser.close();
}

fn parse_paren_expr(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::ParenExpr);
    parser.expect(Token::LParen);
    parse_expr(parser);
    parser.expect(Token::RParen);
    parser.close();
}

pub fn parse_block_expr(parser: &mut Parser<'_>) {
    const BREAK: &[Token] = &[Token::RBrace, Token::Type, Token::Eof];

    parser.open(ast::Kind::BlockExpr);
    parser.expect(Token::LBrace);

    if parser.is(Token::Newline) {
        parse_newlines(parser);

        while !BREAK.contains(&parser.peek(0)) {
            parse_expr(parser);

            if !parser.is(Token::RBrace) {
                parser.expect(Token::Newline);
            }

            parse_newlines(parser);
        }
    } else if !parser.is(Token::RBrace) {
        parse_expr(parser);
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
