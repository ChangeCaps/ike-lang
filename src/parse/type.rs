use crate::{
    ast,
    diagnostic::Diagnostic,
    parse::{Parser, Token, parse_newlines, parse_path},
};

pub fn parse_type(parser: &mut Parser<'_>) {
    parse_term_type(parser);

    if !is_variant(parser) {
        return;
    }

    parser.open_before(ast::Kind::UnionType);

    while is_variant(parser) {
        parse_newlines(parser);
        parser.expect(Token::Pipe);
        parse_term_type(parser);
    }

    parser.close();
}

fn is_variant(parser: &mut Parser<'_>) -> bool {
    let mut i = 0;

    while parser.peek(i) == Token::Newline {
        i += 1;
    }

    parser.peek(i) == Token::Pipe
}

fn parse_term_type(parser: &mut Parser<'_>) {
    match parser.peek(0) {
        Token::Nat => parse_nat_type(parser),
        Token::Int => parse_int_type(parser),
        Token::Num => parse_num_type(parser),
        Token::Str => parse_str_type(parser),
        Token::Bool => parse_bool_type(parser),
        Token::None => parse_none_type(parser),
        Token::Bang => parse_never_type(parser),
        Token::Ident => parse_path_type(parser),
        Token::Quote => parse_generic_type(parser),
        Token::LBrace => parse_record_type(parser),
        Token::LParen => parse_paren_type(parser),

        token => {
            let diagnostic = Diagnostic::error(format!("expected type found `{token}`"))
                .label(parser.span(0), "here");

            parser.error(diagnostic);
        }
    }
}

fn parse_nat_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::NatType);
    parser.expect(Token::Nat);
    parser.close();
}

fn parse_int_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::IntType);
    parser.expect(Token::Int);
    parser.close();
}

fn parse_num_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::NumType);
    parser.expect(Token::Num);
    parser.close();
}

fn parse_str_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::StrType);
    parser.expect(Token::Str);
    parser.close();
}

fn parse_bool_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::BoolType);
    parser.expect(Token::Bool);
    parser.close();
}

fn parse_none_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::NoneType);
    parser.expect(Token::None);
    parser.close();
}

fn parse_never_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::NeverType);
    parser.expect(Token::Bang);
    parser.close();
}

fn parse_path_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::PathType);
    parse_path(parser);
    parser.close();
}

fn parse_generic_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::GenericType);
    parser.expect(Token::Quote);
    parser.expect(Token::Ident);
    parser.close();
}

fn parse_record_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::RecordType);
    parser.expect(Token::LBrace);

    parse_newlines(parser);

    while parser.is(Token::Ident) {
        parse_field(parser);

        if !parser.is(Token::Comma) && !parser.is(Token::Newline) {
            break;
        }

        if parser.is(Token::Comma) {
            parser.expect(Token::Comma);
        }

        parse_newlines(parser);
    }

    parser.expect(Token::RBrace);
    parser.close();
}

fn parse_field(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::Field);

    parser.expect(Token::Ident);
    parser.expect(Token::Colon);
    parse_type(parser);

    parser.close();
}

fn parse_paren_type(parser: &mut Parser<'_>) {
    parser.open(ast::Kind::ParenType);

    parser.expect(Token::LParen);
    parse_type(parser);
    parser.expect(Token::RParen);

    parser.close();
}

#[cfg(test)]
mod tests {
    use crate::{ast, parse::*};

    #[test]
    fn nat() {
        test_parser! {
            parse_type : "nat" =>
            ast::Kind::NatType {
                Token::Nat,
            },
        }
    }

    #[test]
    fn int() {
        test_parser! {
            parse_type : "int" =>
            ast::Kind::IntType {
                Token::Int,
            },
        }
    }

    #[test]
    fn num() {
        test_parser! {
            parse_type : "num" =>
            ast::Kind::NumType {
                Token::Num,
            },
        }
    }

    #[test]
    fn str() {
        test_parser! {
            parse_type : "str" =>
            ast::Kind::StrType {
                Token::Str,
            },
        }
    }

    #[test]
    fn bool() {
        test_parser! {
            parse_type : "bool" =>
            ast::Kind::BoolType {
                Token::Bool,
            },
        }
    }

    #[test]
    fn path() {
        test_parser! {
            parse_type : "a::b" =>
            ast::Kind::PathType {
                ast::Kind::Path {
                    Token::Ident,
                    Token::ColonColon,
                    Token::Ident,
                },
            },
        }
    }

    #[test]
    fn generic() {
        test_parser! {
            parse_type : "'a" =>
            ast::Kind::GenericType {
                Token::Quote,
                Token::Ident,
            },
        }
    }

    #[test]
    fn record() {
        test_parser! {
            parse_type : "{ a: int, b: bool }" =>
            ast::Kind::RecordType {
                Token::LBrace,
                ast::Kind::Field {
                    Token::Ident,
                    Token::Colon,
                    ast::Kind::IntType {
                        Token::Int,
                    },
                },
                Token::Comma,
                ast::Kind::Field {
                    Token::Ident,
                    Token::Colon,
                    ast::Kind::BoolType {
                        Token::Bool,
                    },
                },
                Token::RBrace,
            },
        }

        test_parser! {
            parse_type : "{
                a: int
                b: bool
            }" =>
            ast::Kind::RecordType {
                Token::LBrace,
                Token::Newline,
                ast::Kind::Field {
                    Token::Ident,
                    Token::Colon,
                    ast::Kind::IntType {
                        Token::Int,
                    },
                },
                Token::Newline,
                ast::Kind::Field {
                    Token::Ident,
                    Token::Colon,
                    ast::Kind::BoolType {
                        Token::Bool,
                    },
                },
                Token::Newline,
                Token::RBrace,
            },
        }
    }

    #[test]
    fn union() {
        test_parser! {
            parse_type : "int | str | bool" =>
            ast::Kind::UnionType {
                ast::Kind::IntType {
                    Token::Int,
                },
                Token::Pipe,
                ast::Kind::StrType {
                    Token::Str,
                },
                Token::Pipe,
                ast::Kind::BoolType {
                    Token::Bool,
                },
            },
        }

        test_parser! {
            parse_type : "int
                | str" =>
            ast::Kind::UnionType {
                ast::Kind::IntType {
                    Token::Int,
                },
                Token::Newline,
                Token::Pipe,
                ast::Kind::StrType {
                    Token::Str,
                },
            },
        }
    }
}
