use crate::{
    ast,
    diagnostic::Diagnostic,
    parse::{Parser, parse_block_expr, parse_parameters, parse_type},
};

use super::Token;

pub fn parse_item(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Alias => parse_alias_item(parser),
        Token::Type => parse_type_item(parser),
        Token::Fn => parse_fn_item(parser),
        Token::Extern => parse_extern_item(parser),

        token => {
            let diagnostic = Diagnostic::error(format!("expected item found `{token}`"))
                .label(parser.span(0), "here");

            parser.error(diagnostic);
        }
    }
}

fn parse_alias_item(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::AliasItem);

    parser.expect(Token::Alias);
    parser.expect(Token::Ident);

    parse_generic_parameters(parser);

    parser.expect(Token::Eq);

    parse_type(parser);

    parser.close();
}

fn parse_type_item(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::TypeItem);

    parser.expect(Token::Type);
    parser.expect(Token::Ident);

    parse_generic_parameters(parser);

    parser.expect(Token::Eq);

    parse_type(parser);

    parser.close();
}

fn parse_fn_item(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::FnItem);

    parser.expect(Token::Fn);
    parser.expect(Token::Ident);

    parse_generic_parameters(parser);

    parse_parameters(parser);

    if parser.is(Token::Arrow) {
        parser.expect(Token::Arrow);
        parse_type(parser);
    }

    parse_block_expr(parser);

    parser.close();
}

fn parse_extern_item(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::ExternItem);

    parser.expect(Token::Extern);
    parser.expect(Token::Fn);
    parser.expect(Token::Ident);

    parse_generic_parameters(parser);

    parse_parameters(parser);

    if parser.is(Token::Arrow) {
        parser.expect(Token::Arrow);
        parse_type(parser);
    }

    parse_block_expr(parser);

    parser.close();
}

fn parse_generic_parameters(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::GenericParameters);

    if !parser.is(Token::Lt) {
        parser.close();
        return;
    }

    parser.expect(Token::Lt);

    while parser.is(Token::Quote) {
        parse_generic_parameter(parser);

        if !parser.is(Token::Gt) {
            parser.expect(Token::Comma);
        }
    }

    parser.expect(Token::Gt);

    parser.close();
}

fn parse_generic_parameter(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::GenericParameter);

    parser.expect(Token::Quote);
    parser.expect(Token::Ident);

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
                ast::Kind::GenericParameters {},
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
            parse_item : "fn foo(a: int, b: num) -> bool {}" =>
            ast::Kind::FnItem {
                Token::Fn,
                Token::Ident,
                ast::Kind::GenericParameters {},
                ast::Kind::Params {
                    Token::LParen,
                    ast::Kind::Param {
                        ast::Kind::BindingPattern {
                            Token::Ident,
                        },
                        Token::Colon,
                        ast::Kind::IntType {
                            Token::Int,
                        },
                    },
                    Token::Comma,
                    ast::Kind::Param {
                        ast::Kind::BindingPattern {
                            Token::Ident,
                        },
                        Token::Colon,
                        ast::Kind::NumType {
                            Token::Num,
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
