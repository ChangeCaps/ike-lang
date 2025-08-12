use std::{
    collections::{BTreeMap, HashMap},
    error::Error,
    fs,
    path::{Path, PathBuf},
    str::FromStr,
};

use lsp_server::{Connection, IoThreads, Message, Notification, RequestId, Response};
use lsp_types::{
    DiagnosticSeverity, DidChangeTextDocumentParams, DidOpenTextDocumentParams, InitializeParams,
    Position, PositionEncodingKind, PublishDiagnosticsParams, Range, SaveOptions, SemanticToken,
    SemanticTokenModifier, SemanticTokenType, SemanticTokens, SemanticTokensFullOptions,
    SemanticTokensLegend, SemanticTokensOptions, SemanticTokensParams, ServerCapabilities,
    TextDocumentSyncKind, TextDocumentSyncOptions, Uri,
    notification::{
        DidChangeTextDocument, DidOpenTextDocument, Notification as _, PublishDiagnostics,
    },
    request::{Request, SemanticTokensFullRequest},
};

use crate::{
    ast,
    diagnostic::{Diagnostic, Level, Sid, Source, Sources, Span},
    parse::{self, TokenStream},
};

#[allow(dead_code)]
struct BuildOptions {
    workspace_folder: PathBuf,
}

pub struct LanguageServer {
    pub connection: Connection,
    pub io_threads: IoThreads,
    pub params: InitializeParams,

    pub sources: Sources,

    /// A map from absolute paths to sources.
    pub sids: HashMap<PathBuf, Sid>,

    pub diagnostics: HashMap<Sid, Vec<Diagnostic>>,

    pub tokens: HashMap<Sid, TokenStream>,
    pub asts: HashMap<Sid, ast::File>,
}

impl LanguageServer {
    fn capabilities() -> ServerCapabilities {
        ServerCapabilities {
            position_encoding: Some(PositionEncodingKind::UTF8),
            text_document_sync: Some(
                TextDocumentSyncOptions {
                    open_close: Some(true),
                    change: Some(TextDocumentSyncKind::FULL),
                    will_save: None,
                    will_save_wait_until: None,
                    save: Some(
                        SaveOptions {
                            include_text: Some(false),
                        }
                        .into(),
                    ),
                }
                .into(),
            ),
            semantic_tokens_provider: Some(
                SemanticTokensOptions {
                    legend: SemanticTokensLegend {
                        token_types: TOKEN_TYPES.to_vec(),
                        token_modifiers: TOKEN_MODIFIERS.to_vec(),
                    },
                    range: Some(true),
                    full: Some(SemanticTokensFullOptions::Delta { delta: Some(true) }),
                    work_done_progress_options: Default::default(),
                }
                .into(),
            ),
            ..Default::default()
        }
    }

    pub fn new() -> Result<Self, Box<dyn Error>> {
        let (connection, io_threads) = Connection::stdio();

        let params = connection.initialize(serde_json::to_value(Self::capabilities())?)?;
        let params: InitializeParams = serde_json::from_value(params)?;

        Ok(Self {
            connection,
            io_threads,
            params,
            sources: Sources::new(),
            sids: HashMap::new(),
            diagnostics: HashMap::new(),
            tokens: HashMap::new(),
            asts: HashMap::new(),
        })
    }

    pub fn run(mut self) -> Result<(), Box<dyn Error>> {
        for msg in self.connection.receiver.clone().iter() {
            match msg {
                Message::Request(request) => {
                    if self.connection.handle_shutdown(&request)? {
                        break;
                    }

                    if request.method == SemanticTokensFullRequest::METHOD {
                        let params: SemanticTokensParams = serde_json::from_value(request.params)?;
                        self.handle_token_semantics(params, request.id)?
                    }
                }

                Message::Response(_) => {}

                Message::Notification(notif) => match notif.method.as_str() {
                    DidChangeTextDocument::METHOD => {
                        let params: DidChangeTextDocumentParams =
                            serde_json::from_value(notif.params)?;

                        let path = Path::new(params.text_document.uri.path().as_str());
                        let content = params.content_changes.into_iter().next().unwrap().text;
                        self.content_changed(path, content);

                        self.publish_diagnostics()?;
                    }

                    DidOpenTextDocument::METHOD => {
                        let params: DidOpenTextDocumentParams =
                            serde_json::from_value(notif.params)?;

                        let path = Path::new(params.text_document.uri.path().as_str());
                        let content = fs::read_to_string(path)?;
                        self.content_changed(path, content);

                        self.publish_diagnostics()?;
                    }

                    _ => {}
                },
            }
        }

        self.io_threads.join()?;

        Ok(())
    }

    fn publish_diagnostics(&self) -> Result<(), Box<dyn Error>> {
        let mut diagnostics: HashMap<PathBuf, Vec<lsp_types::Diagnostic>> = HashMap::new();

        for path in self.sids.keys() {
            diagnostics.insert(path.clone(), Vec::new());
        }

        for diagnostic in self.diagnostics.values().flatten() {
            for label in &diagnostic.labels {
                let source = &self.sources[label.span.id];
                let (start_line, start_column) =
                    label.span.compute_start_line_column(&source.content);
                let (end_line, end_column) = label.span.compute_end_line_column(&source.content);

                diagnostics
                    .entry(source.path.clone())
                    .or_default()
                    .push(lsp_types::Diagnostic {
                        message: diagnostic.message.clone(),

                        severity: match diagnostic.level {
                            Level::Error => Some(DiagnosticSeverity::ERROR),
                            Level::Warn => Some(DiagnosticSeverity::WARNING),
                            Level::Note => Some(DiagnosticSeverity::INFORMATION),
                        },

                        range: Range {
                            start: Position {
                                line: start_line - 1,
                                character: start_column - 1,
                            },
                            end: Position {
                                line: end_line - 1,
                                character: end_column - 1,
                            },
                        },
                        ..Default::default()
                    });
            }
        }

        for (path, diagnostics) in diagnostics {
            let params = PublishDiagnosticsParams {
                uri: Uri::from_str(&format!("file://{}", path.display())).unwrap(),
                diagnostics,
                version: None,
            };

            let notification = Notification::new(
                PublishDiagnostics::METHOD.to_string(),
                params, //
            );

            (self.connection.sender).send(Message::Notification(notification))?;
        }

        Ok(())
    }

    fn content_changed(&mut self, path: &Path, content: String) {
        match self.sids.get(path).copied() {
            Some(sid) => {
                self.sources[sid].content = content;
                self.tokens.remove(&sid);
                self.asts.remove(&sid);
                self.diagnostics.get_mut(&sid).map(Vec::clear);

                self.tokenize(sid);
                self.parse(sid);
            }
            None => {
                let sid = self.sources.add(Source {
                    path: path.to_path_buf(),
                    content,
                });

                self.sids.insert(path.to_path_buf(), sid);
                self.tokenize(sid);
                self.parse(sid);
            }
        }
    }

    fn tokenize(&mut self, sid: Sid) {
        if self.tokens.contains_key(&sid) {
            return;
        }

        let mut emitter = Vec::new();

        let input = &self.sources[sid].content;
        let tokens = match parse::tokenize(input, sid, &mut emitter) {
            Ok(tokens) => tokens,
            Err(tokens) => tokens,
        };

        self.diagnostics.entry(sid).or_default().extend(emitter);
        self.tokens.insert(sid, tokens);
    }

    fn parse(&mut self, sid: Sid) {
        if self.asts.contains_key(&sid) {
            return;
        }

        let mut emitter = Vec::new();

        let tokens = &self.tokens[&sid];
        let file = match parse::parse_file(&mut tokens.clone(), &mut emitter) {
            Ok(file) => file,
            Err(file) => file,
        };

        self.diagnostics.entry(sid).or_default().extend(emitter);
        self.asts.insert(sid, file);
    }

    fn handle_token_semantics(
        &self,
        params: SemanticTokensParams,
        request_id: RequestId,
    ) -> Result<(), Box<dyn Error>> {
        let path = Path::new(params.text_document.uri.path().as_str());
        let sid = self.sids[path];

        let content = &self.sources[sid].content;

        let mut semantics = Semantics::default();

        if let Some(tokens) = self.tokens.get(&sid) {
            Self::add_token_semantics(tokens, &mut semantics);
        }

        if let Some(ast) = self.asts.get(&sid) {
            Self::add_ast_semantics(ast, &mut semantics);
        }

        let mut data = Vec::new();

        let mut prev_line = 1;
        let mut prev_column = 1;

        for (span, token_type, m) in semantics.semantics.into_values() {
            let (line, column) = span.compute_start_line_column(content);

            if line != prev_line {
                prev_column = 1;
            }

            data.push(SemanticToken {
                delta_line: line - prev_line,
                delta_start: column - prev_column,
                length: span.hi - span.lo,
                token_type,
                token_modifiers_bitset: m,
            });

            prev_line = line;
            prev_column = column;
        }

        let result = SemanticTokens {
            result_id: None,
            data,
        };

        let response = Response::new_ok(request_id, result);
        self.connection.sender.send(Message::Response(response))?;

        Ok(())
    }

    fn add_token_semantics(tokens: &parse::TokenStream, semantics: &mut Semantics) {
        for (token, span) in tokens {
            if let Some([ty, m]) = token_semantics(token) {
                semantics.add(*span, ty, m);
            }
        }
    }

    fn add_ast_semantics(ast: &ast::File, semantics: &mut Semantics) {
        for item in &ast.items {
            match item {
                ast::Item::Import(ast) => {
                    semantics.add(ast.span, KEYWORD, 0);
                }

                ast::Item::Newtype(ast) => {
                    semantics.add(ast.span, KEYWORD, 0);

                    Self::add_ast_type_name_semantics(&ast.name, semantics);

                    for (_, span) in &ast.generics {
                        semantics.add(*span, PROPERTY, 0);
                    }

                    match ast.kind {
                        ast::NewtypeKind::Union(ref variants) => {
                            for variant in variants {
                                Self::add_ast_variant_name_semantics(&variant.name, semantics);

                                if let Some(ref ty) = variant.ty {
                                    Self::add_ast_type_semantics(ty, semantics);
                                }
                            }
                        }

                        ast::NewtypeKind::Record(ref fields) => {
                            for field in fields {
                                semantics.add(field.span, PROPERTY, 0);
                                Self::add_ast_type_semantics(&field.ty, semantics);
                            }
                        }

                        ast::NewtypeKind::Alias(ref alias) => {
                            Self::add_ast_type_semantics(alias, semantics);
                        }
                    }
                }

                ast::Item::Function(ast) => {
                    semantics.add(ast.span, KEYWORD, 0);

                    Self::add_ast_fn_name_semantics(&ast.name, semantics);

                    if let Some(ref body) = ast.body {
                        Self::add_ast_expr_semantics(body, semantics);
                    }
                }

                ast::Item::Ascription(ast) => {
                    semantics.add(ast.span, KEYWORD, 0);

                    Self::add_ast_fn_name_semantics(&ast.name, semantics);
                    Self::add_ast_type_semantics(&ast.ty, semantics);
                }

                ast::Item::Extern(ast) => {
                    semantics.add(ast.span, KEYWORD, 0);

                    Self::add_ast_fn_name_semantics(&ast.name, semantics);
                    Self::add_ast_type_semantics(&ast.ty, semantics);
                }
            }
        }
    }

    fn add_ast_fn_name_semantics(ast: &ast::Path, semantics: &mut Semantics) {
        let name_len = ast.segments.last().unwrap().len() as u32;

        let mut span = ast.span;
        span.lo = span.hi - name_len;
        semantics.add(span, FUNCTION, 0);

        if ast.span.hi - ast.span.lo > name_len {
            let mut span = ast.span;
            span.hi -= name_len;
            semantics.add(span, NAMESPACE, 0);
        }
    }

    fn add_ast_type_name_semantics(ast: &ast::Path, semantics: &mut Semantics) {
        let name_len = ast.segments.last().unwrap().len() as u32;

        let mut span = ast.span;
        span.lo = span.hi - name_len;
        semantics.add(span, TYPE, 0);

        if ast.span.hi - ast.span.lo > name_len {
            let mut span = ast.span;
            span.hi -= name_len;
            semantics.add(span, NAMESPACE, 0);
        }
    }

    fn add_ast_variant_name_semantics(ast: &ast::Path, semantics: &mut Semantics) {
        let name_len = ast.segments.last().unwrap().len() as u32;

        let mut span = ast.span;
        span.lo = span.hi - name_len;
        semantics.add(span, ENUM_MEMBER, 0);

        if ast.span.hi - ast.span.lo > name_len {
            let mut span = ast.span;
            span.hi -= name_len;
            semantics.add(span, NAMESPACE, 0);
        }
    }

    fn add_ast_type_semantics(ast: &ast::Type, semantics: &mut Semantics) {
        match &ast.kind {
            ast::TypeKind::Int
            | ast::TypeKind::Str
            | ast::TypeKind::Bool
            | ast::TypeKind::Unit
            | ast::TypeKind::Inferred => {}

            ast::TypeKind::Path(path, generics) => {
                Self::add_ast_type_name_semantics(path, semantics);

                for generic in generics {
                    Self::add_ast_type_semantics(generic, semantics);
                }
            }

            ast::TypeKind::Tuple(items) => {
                for item in items {
                    Self::add_ast_type_semantics(item, semantics);
                }
            }

            ast::TypeKind::List(item) => Self::add_ast_type_semantics(item, semantics),

            ast::TypeKind::Function(input, output) => {
                Self::add_ast_type_semantics(input, semantics);
                Self::add_ast_type_semantics(output, semantics);
            }

            ast::TypeKind::Generic(_) => semantics.add(ast.span, PROPERTY, 0),
        }
    }

    fn add_ast_pattern_semantics(ast: &ast::Pattern, semantics: &mut Semantics) {
        match &ast.kind {
            ast::PatternKind::Wildcard
            | ast::PatternKind::Bool(_)
            | ast::PatternKind::Int(_)
            | ast::PatternKind::String(_) => {}

            ast::PatternKind::Path(_) => {}

            ast::PatternKind::Variant(path, pattern) => {
                Self::add_ast_variant_name_semantics(path, semantics);
                Self::add_ast_pattern_semantics(pattern, semantics);
            }

            ast::PatternKind::Tuple(patterns) => {
                for pattern in patterns {
                    Self::add_ast_pattern_semantics(pattern, semantics);
                }
            }

            ast::PatternKind::List(patterns, pattern) => {
                for pattern in patterns {
                    Self::add_ast_pattern_semantics(pattern, semantics);
                }

                if let Some(pattern) = pattern {
                    Self::add_ast_pattern_semantics(pattern, semantics);
                }
            }
        }
    }

    fn add_ast_expr_semantics(ast: &ast::Expr, semantics: &mut Semantics) {
        match &ast.kind {
            ast::ExprKind::Int(_) | ast::ExprKind::Bool(_) | ast::ExprKind::String(_) => {}

            ast::ExprKind::Format(parts) => {
                for part in parts {
                    Self::add_ast_expr_semantics(part, semantics);
                }
            }

            ast::ExprKind::Path(_) => {}

            ast::ExprKind::Let(pattern, expr) => {
                Self::add_ast_pattern_semantics(pattern, semantics);
                Self::add_ast_expr_semantics(expr, semantics);
            }

            ast::ExprKind::Record(path, items) => {
                Self::add_ast_type_name_semantics(path, semantics);

                for (_, item, span) in items {
                    Self::add_ast_expr_semantics(item, semantics);
                    semantics.add(*span, PROPERTY, 0);
                }
            }

            ast::ExprKind::With(target, items) => {
                Self::add_ast_expr_semantics(target, semantics);

                for (_, item, span) in items {
                    Self::add_ast_expr_semantics(item, semantics);
                    semantics.add(*span, PROPERTY, 0);
                }
            }

            ast::ExprKind::List(items, rest) => {
                for item in items {
                    Self::add_ast_expr_semantics(item, semantics);
                }

                if let Some(rest) = rest {
                    Self::add_ast_expr_semantics(rest, semantics);
                }
            }

            ast::ExprKind::Tuple(items) => {
                for item in items {
                    Self::add_ast_expr_semantics(item, semantics);
                }
            }

            ast::ExprKind::Lambda(_, body) => {
                Self::add_ast_expr_semantics(body, semantics);
            }

            ast::ExprKind::Binary(_, _, lhs, rhs) => {
                Self::add_ast_expr_semantics(lhs, semantics);
                Self::add_ast_expr_semantics(rhs, semantics);
            }

            ast::ExprKind::Try(value) => {
                Self::add_ast_expr_semantics(value, semantics);
            }

            ast::ExprKind::Call(target, input) => {
                if let ast::ExprKind::Path(ref target) = target.kind {
                    Self::add_ast_fn_name_semantics(target, semantics);
                } else {
                    Self::add_ast_expr_semantics(target, semantics);
                }

                Self::add_ast_expr_semantics(input, semantics);
            }

            ast::ExprKind::Field(target, _, span) => {
                Self::add_ast_expr_semantics(target, semantics);
                semantics.add(*span, PROPERTY, 0);
            }

            ast::ExprKind::Match(target, arms) => {
                Self::add_ast_expr_semantics(target, semantics);

                for arm in arms {
                    Self::add_ast_pattern_semantics(&arm.pattern, semantics);
                    Self::add_ast_expr_semantics(&arm.expr, semantics);
                }
            }

            ast::ExprKind::Block(exprs) => {
                for expr in exprs {
                    Self::add_ast_expr_semantics(expr, semantics);
                }
            }
        }
    }
}

#[derive(Default)]
struct Semantics {
    semantics: BTreeMap<u32, (Span, u32, u32)>,
}

impl Semantics {
    fn add(&mut self, span: Span, token_type: u32, token_modifiers: u32) {
        (self.semantics).insert(span.lo, (span, token_type, token_modifiers));
    }
}

const TOKEN_TYPES: &[SemanticTokenType] = &[
    SemanticTokenType::KEYWORD,
    SemanticTokenType::VARIABLE,
    SemanticTokenType::NUMBER,
    SemanticTokenType::OPERATOR,
    SemanticTokenType::STRING,
    SemanticTokenType::TYPE,
    SemanticTokenType::FUNCTION,
    SemanticTokenType::NAMESPACE,
    SemanticTokenType::PROPERTY,
    SemanticTokenType::COMMENT,
    SemanticTokenType::ENUM,
    SemanticTokenType::ENUM_MEMBER,
];

const TOKEN_MODIFIERS: &[SemanticTokenModifier] = &[SemanticTokenModifier::STATIC];

const KEYWORD: u32 = 0;
#[allow(dead_code)]
const VARIABLE: u32 = 1;
const NUMBER: u32 = 2;
const OPERATOR: u32 = 3;
const STRING: u32 = 4;
const TYPE: u32 = 5;
const FUNCTION: u32 = 6;
const NAMESPACE: u32 = 7;
const PROPERTY: u32 = 8;
const COMMENT: u32 = 9;
#[allow(dead_code)]
const ENUM: u32 = 10;
const ENUM_MEMBER: u32 = 11;

const STATIC: u32 = 1;

fn token_semantics(token: &parse::Token) -> Option<[u32; 2]> {
    Some(match token {
        parse::Token::Ident(_) => return None,
        parse::Token::String(_) => [STRING, 0],
        parse::Token::Integer(_) => [NUMBER, 0],
        parse::Token::Comment(_) => [COMMENT, 0],
        parse::Token::Whitespace | parse::Token::Newline | parse::Token::Eof => return None,

        parse::Token::And
        | parse::Token::Let
        | parse::Token::Or
        | parse::Token::Match
        | parse::Token::Try
        | parse::Token::With => [KEYWORD, 0],

        parse::Token::False | parse::Token::True => [ENUM_MEMBER, STATIC],
        parse::Token::Bool | parse::Token::Int | parse::Token::Str => [TYPE, 0],

        parse::Token::DotDot
        | parse::Token::RArrow
        | parse::Token::LArrow
        | parse::Token::EqEq
        | parse::Token::NotEq
        | parse::Token::LtEq
        | parse::Token::GtEq
        | parse::Token::LtPipe
        | parse::Token::PipeGt
        | parse::Token::Semi
        | parse::Token::Colon
        | parse::Token::Comma
        | parse::Token::Dot
        | parse::Token::Pound
        | parse::Token::Under
        | parse::Token::Plus
        | parse::Token::Minus
        | parse::Token::Star
        | parse::Token::Slash
        | parse::Token::Backslash
        | parse::Token::Percent
        | parse::Token::Amp
        | parse::Token::Pipe
        | parse::Token::Caret
        | parse::Token::Bang
        | parse::Token::Question
        | parse::Token::Quote
        | parse::Token::Eq
        | parse::Token::Tilde
        | parse::Token::Lt
        | parse::Token::Gt
        | parse::Token::LParen
        | parse::Token::RParen
        | parse::Token::LBrace
        | parse::Token::RBrace
        | parse::Token::LBracket
        | parse::Token::RBracket => [OPERATOR, 0],

        parse::Token::ColonColon => [NAMESPACE, 0],
    })
}
