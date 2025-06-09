use crate::{
    ast::{
        Ascription, Extern, Field, Function, Import, Item, ItemName, Module, Newtype, NewtypeKind,
        Variant,
    },
    diagnostic::Diagnostic,
};

use super::{
    Token, TokenStream, consume_newlines, parse_block_expr, parse_expr, parse_ident,
    parse_irrefutable_pattern, parse_path, parse_type,
};

fn parse_name(tokens: &mut TokenStream) -> Result<ItemName, Diagnostic> {
    let mut segments = Vec::new();

    let (first, mut span) = parse_ident(tokens)?;
    segments.push(first);

    while tokens.is(&Token::ColonColon) {
        tokens.consume();

        let (segment, segment_span) = parse_ident(tokens)?;
        segments.push(segment);
        span = span.join(segment_span);
    }

    Ok(ItemName { segments, span })
}

fn parse_import(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    tokens.expect(&Token::Import)?;

    let path = parse_path(tokens)?;

    let span = path.span;
    let import = Import { path, span };
    Ok(Item::Import(import))
}

fn parse_fields(tokens: &mut TokenStream) -> Result<Vec<Field>, Diagnostic> {
    tokens.expect(&Token::LBrace)?;

    let mut fields = Vec::new();

    consume_newlines(tokens);

    while !tokens.is(&Token::RBrace) {
        let (name, span) = parse_ident(tokens)?;

        tokens.expect(&Token::Colon)?;

        let ty = parse_type(tokens)?;

        fields.push(Field { name, ty, span });

        if !(tokens.is(&Token::RBrace) || tokens.is(&Token::Newline)) {
            tokens.expect(&Token::Semi)?;
        }

        consume_newlines(tokens);
    }

    tokens.expect(&Token::RBrace)?;

    Ok(fields)
}

fn parse_variant(tokens: &mut TokenStream) -> Result<Variant, Diagnostic> {
    let (name, span) = parse_ident(tokens)?;

    let ty = if tokens.is(&Token::Newline) || tokens.is(&Token::Pipe) {
        None
    } else {
        Some(parse_type(tokens)?)
    };

    Ok(Variant { name, ty, span })
}

fn is_variant(tokens: &mut TokenStream) -> bool {
    let mut n = 0;

    while tokens.nth_is(n, &Token::Newline) {
        n += 1;
    }

    tokens.nth_is(n, &Token::Pipe)
}

fn parse_newtype(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    tokens.expect(&Token::Type)?;

    let name = parse_name(tokens)?;

    let mut generics = Vec::new();

    if tokens.is(&Token::Lt) {
        tokens.consume();

        while !tokens.is(&Token::Gt) {
            tokens.expect(&Token::Quote)?;
            let (name, _) = parse_ident(tokens)?;
            generics.push(name);

            if tokens.is(&Token::Gt) {
                break;
            }

            tokens.expect(&Token::Comma)?;
        }

        tokens.expect(&Token::Gt)?;
    }

    tokens.expect(&Token::Eq)?;

    let (token, _) = tokens.peek();

    match token {
        Token::LBrace => {
            let fields = parse_fields(tokens)?;

            let span = name.span;
            let kind = NewtypeKind::Record(fields);

            let newtype = Newtype {
                name,
                generics,
                kind,
                span,
            };

            Ok(Item::Newtype(newtype))
        }

        _ => {
            let mut variants = vec![parse_variant(tokens)?];

            while is_variant(tokens) {
                consume_newlines(tokens);

                tokens.expect(&Token::Pipe)?;

                let variant = parse_variant(tokens)?;
                variants.push(variant);
            }

            let span = name.span;
            let kind = NewtypeKind::Union(variants);

            let newtype = Newtype {
                name,
                generics,
                kind,
                span,
            };

            Ok(Item::Newtype(newtype))
        }
    }
}

fn parse_function(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    tokens.expect(&Token::Fn)?;

    let name = parse_name(tokens)?;

    if tokens.is(&Token::Colon) {
        tokens.consume();

        let ty = parse_type(tokens)?;

        let span = name.span.join(ty.span);
        let ascription = Ascription { name, ty, span };
        return Ok(Item::Ascription(ascription));
    }

    let mut params = Vec::new();

    while !(tokens.is(&Token::LBrace) || tokens.is(&Token::RArrow)) {
        let param = parse_irrefutable_pattern(tokens)?;
        params.push(param);
    }

    let (token, _) = tokens.peek();

    let body = match token {
        Token::LBrace => Some(parse_block_expr(tokens)?),

        Token::RArrow => {
            tokens.consume();
            Some(parse_expr(tokens)?)
        }

        _ => unreachable!(),
    };

    let function = Function { name, params, body };
    Ok(Item::Function(function))
}

fn parse_extern(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    tokens.expect(&Token::Extern)?;

    let name = parse_name(tokens)?;

    tokens.expect(&Token::Colon)?;

    let ty = parse_type(tokens)?;

    let span = name.span.join(ty.span);

    let r#extern = Extern { name, ty, span };

    Ok(Item::Extern(r#extern))
}

fn parse_item(tokens: &mut TokenStream) -> Result<Item, Diagnostic> {
    let (token, span) = tokens.peek();

    match token {
        Token::Fn => parse_function(tokens),
        Token::Type => parse_newtype(tokens),
        Token::Import => parse_import(tokens),
        Token::Extern => parse_extern(tokens),

        _ => {
            let diagnostic = Diagnostic::error("expected item").with_span(span);
            Err(diagnostic)
        }
    }
}

pub fn parse_module(tokens: &mut TokenStream) -> Result<Module, Diagnostic> {
    let mut items = Vec::new();

    consume_newlines(tokens);

    while !tokens.is(&Token::Eof) {
        let item = parse_item(tokens)?;
        items.push(item);

        consume_newlines(tokens);
    }

    Ok(Module { items })
}
