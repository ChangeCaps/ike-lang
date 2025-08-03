use crate::{
    ast::{Pattern, PatternKind},
    diagnostic::Diagnostic,
};

use super::{Token, TokenStream, parse_path};

fn is_pattern(tokens: &TokenStream) -> bool {
    let (token, _) = tokens.peek();

    matches!(
        token,
        Token::Under
            | Token::True
            | Token::False
            | Token::Ident(_)
            | Token::String(_)
            | Token::LParen
            | Token::LBracket
    )
}

fn parse_pattern_term(
    tokens: &mut TokenStream,
    allow_refutable: bool,
) -> Result<Pattern, Diagnostic> {
    let (token, span) = tokens.peek();

    match token {
        Token::Under => {
            tokens.consume();

            let kind = PatternKind::Wildcard;
            Ok(Pattern { kind, span })
        }

        Token::True if allow_refutable => {
            tokens.consume();

            let kind = PatternKind::Bool(true);
            Ok(Pattern { kind, span })
        }

        Token::False if allow_refutable => {
            tokens.consume();

            let kind = PatternKind::Bool(false);
            Ok(Pattern { kind, span })
        }

        Token::Ident(_) => {
            let path = parse_path(tokens)?;

            if is_pattern(tokens) && allow_refutable {
                let pattern = parse_pattern_term(tokens, allow_refutable)?;

                let span = span.join(pattern.span);
                let kind = PatternKind::Variant(path, Box::new(pattern));
                return Ok(Pattern { kind, span });
            }

            let kind = PatternKind::Path(path);
            Ok(Pattern { kind, span })
        }

        Token::Integer(value) => {
            tokens.consume();

            let kind = PatternKind::Int(value);
            Ok(Pattern { kind, span })
        }

        Token::String(string) => {
            tokens.consume();

            let string = string.replace("{{", "{").replace("}}", "}");
            let kind = PatternKind::String(string);
            Ok(Pattern { kind, span })
        }

        Token::LParen => {
            tokens.consume();
            let pattern = parse_pattern_impl(tokens, allow_refutable)?;
            tokens.expect(&Token::RParen)?;

            Ok(pattern)
        }

        Token::LBracket if allow_refutable => {
            tokens.consume();

            let mut patterns = Vec::new();
            let mut rest = None;

            while !tokens.is(&Token::RBracket) {
                if tokens.is(&Token::DotDot) {
                    tokens.consume();

                    let pattern = match tokens.is(&Token::RBracket) {
                        true => Pattern {
                            kind: PatternKind::Wildcard,
                            span,
                        },
                        false => parse_pattern_impl(tokens, allow_refutable)?,
                    };

                    rest = Some(Box::new(pattern));

                    break;
                }

                let pattern = parse_pattern_impl(tokens, allow_refutable)?;
                patterns.push(pattern);

                if !tokens.is(&Token::RBracket) {
                    tokens.expect(&Token::Semi)?;
                }
            }

            let end = tokens.expect(&Token::RBracket)?;

            let span = span.join(end);
            let kind = PatternKind::List(patterns, rest);
            Ok(Pattern { kind, span })
        }

        _ => {
            let diagnostic = Diagnostic::error("expected pattern").with_span(span);
            Err(diagnostic)
        }
    }
}

fn parse_pattern_impl(
    tokens: &mut TokenStream,
    allow_refutable: bool,
) -> Result<Pattern, Diagnostic> {
    let pattern = parse_pattern_term(tokens, allow_refutable)?;

    if !tokens.is(&Token::Comma) {
        return Ok(pattern);
    }

    let mut span = pattern.span;
    let mut patterns = vec![pattern];

    while tokens.is(&Token::Comma) {
        tokens.consume();

        let pattern = parse_pattern_term(tokens, allow_refutable)?;
        span = span.join(pattern.span);
        patterns.push(pattern);
    }

    let kind = PatternKind::Tuple(patterns);
    Ok(Pattern { kind, span })
}

pub fn parse_pattern(tokens: &mut TokenStream) -> Result<Pattern, Diagnostic> {
    parse_pattern_impl(tokens, true)
}

pub fn parse_irrefutable_pattern(tokens: &mut TokenStream) -> Result<Pattern, Diagnostic> {
    parse_pattern_impl(tokens, false)
}
