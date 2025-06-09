use crate::{
    ast::{Type, TypeKind},
    diagnostic::Diagnostic,
};

use super::{Token, TokenStream, parse_ident, parse_path};

fn parse_term_type(tokens: &mut TokenStream) -> Result<Type, Diagnostic> {
    let (token, span) = tokens.peek();

    match token {
        Token::Int => {
            tokens.consume();

            let kind = TypeKind::Int;
            Ok(Type { kind, span })
        }

        Token::Str => {
            tokens.consume();

            let kind = TypeKind::Str;
            Ok(Type { kind, span })
        }

        Token::Bool => {
            tokens.consume();

            let kind = TypeKind::Bool;
            Ok(Type { kind, span })
        }

        Token::Under => {
            tokens.consume();

            let kind = TypeKind::Inferred;
            Ok(Type { kind, span })
        }

        Token::Quote => {
            tokens.consume();

            let (name, name_span) = parse_ident(tokens)?;
            let kind = TypeKind::Generic(name);
            let span = span.join(name_span);
            Ok(Type { kind, span })
        }

        Token::Ident(_) => {
            let name = parse_path(tokens)?;

            let span = name.span;
            let kind = TypeKind::Path(name);
            Ok(Type { kind, span })
        }

        Token::LParen => {
            tokens.consume();
            let item = parse_type(tokens)?;
            tokens.expect(&Token::RParen)?;

            Ok(item)
        }

        Token::LBrace => {
            tokens.consume();
            let end = tokens.expect(&Token::RBrace)?;

            let kind = TypeKind::Unit;
            let span = span.join(end);
            Ok(Type { kind, span })
        }

        Token::LBracket => {
            tokens.consume();
            let item = parse_type(tokens)?;
            let end = tokens.expect(&Token::RBracket)?;

            let kind = TypeKind::List(Box::new(item));
            let span = span.join(end);
            Ok(Type { kind, span })
        }

        _ => {
            let diagnostic = Diagnostic::error("expected type").with_span(span);
            Err(diagnostic)
        }
    }
}

fn parse_tuple_type(tokens: &mut TokenStream) -> Result<Type, Diagnostic> {
    let ty = parse_term_type(tokens)?;

    if !tokens.is(&Token::Star) {
        return Ok(ty);
    }

    let mut span = ty.span;
    let mut items = vec![ty];

    while tokens.is(&Token::Star) {
        tokens.consume();

        let item = parse_term_type(tokens)?;
        span = span.join(item.span);
        items.push(item);
    }

    let kind = TypeKind::Tuple(items);
    Ok(Type { kind, span })
}

pub fn parse_type(tokens: &mut TokenStream) -> Result<Type, Diagnostic> {
    let mut ty = parse_tuple_type(tokens)?;

    if tokens.is(&Token::RArrow) {
        tokens.consume();

        let output = parse_type(tokens)?;
        let span = ty.span.join(output.span);
        let kind = TypeKind::Function(Box::new(ty), Box::new(output));
        ty = Type { kind, span };
    }

    Ok(ty)
}
