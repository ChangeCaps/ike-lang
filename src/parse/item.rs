use crate::{
    ast,
    diagnostic::Diagnostic,
    parse::{Parser, parse_block_expr, parse_params, parse_type},
};

use super::Token;

pub(crate) fn parse_item(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Type => parse_type_item(parser),
        Token::Fn => parse_fn_item(parser),

        token => {
            let diagnostic = Diagnostic::error(format!("expected item found `{token}`"))
                .label(parser.span(0), "here");

            parser.error(diagnostic);
        }
    }
}

fn parse_type_item(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::TypeItem);

    parser.expect(Token::Type);
    parser.expect(Token::Ident);
    parser.expect(Token::Eq);
    parse_type(parser);

    parser.close();
}

fn parse_fn_item(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::FnItem);

    parser.expect(Token::Fn);
    parser.expect(Token::Ident);

    parse_params(parser);

    if parser.is(Token::Arrow) {
        parser.expect(Token::Arrow);
        parse_type(parser);
    }

    parse_block_expr(parser);

    parser.close();
}

#[cfg(test)]
mod tests {
    use crate::{ast, parse::*};

    #[test]
    fn r#type() {
        test_parser! {
            parse_item : "type t = 'a | int" =>
            ast::Kind::TypeItem {
                Token::Type,
                Token::Ident,
                Token::Eq,
                ast::Kind::UnionType {
                    ast::Kind::GenericType {
                        Token::Quote,
                        Token::Ident,
                    },
                    Token::Pipe,
                    ast::Kind::IntType {
                        Token::Int,
                    },
                },
            },
        };
    }

    #[test]
    fn r#fn() {
        test_parser! {
            parse_item : "fn foo(a: int, b: float) -> bool {}" =>
            ast::Kind::FnItem {
                Token::Fn,
                Token::Ident,
                ast::Kind::Params {
                    Token::LParen,
                    ast::Kind::Param {
                        Token::Ident,
                        Token::Colon,
                        ast::Kind::IntType {
                            Token::Int,
                        },
                    },
                    Token::Comma,
                    ast::Kind::Param {
                        Token::Ident,
                        Token::Colon,
                        ast::Kind::FloatType {
                            Token::Float,
                        },
                    },
                    Token::RParen,
                },
                Token::Arrow,
                ast::Kind::BoolType {
                    Token::Bool,
                },
                ast::Kind::BlockExpr {
                    Token::LBrace,
                    Token::RBrace,
                }
            },
        }
    }
}
