use std::{
    cmp,
    collections::HashMap,
    fmt,
    hash::{Hash, Hasher},
    sync::atomic::{AtomicU64, Ordering},
};

use crate::diagnostic::Span;

use super::Tid;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum Type {
    Var(Var),
    App(App),
}

impl Type {
    pub fn with_span(self, span: Span) -> Self {
        match self {
            Type::Var(var) => Type::Var(var.with_span(span)),
            Type::App(app) => Type::App(App {
                kind: app.kind,
                span,
            }),
        }
    }

    pub fn dummy() -> Self {
        Self::unit(Span::dummy())
    }

    pub fn infer(span: Span) -> Self {
        Type::Var(Var::fresh(span))
    }

    pub const fn int(span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Int,
            span,
        })
    }

    pub const fn str(span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Str,
            span,
        })
    }

    pub const fn bool(span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Bool,
            span,
        })
    }

    pub const fn unit(span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Unit,
            span,
        })
    }

    pub fn list(ty: Type, span: Span) -> Self {
        Type::App(App {
            kind: AppKind::List(Box::new(ty)),
            span,
        })
    }

    pub fn tuple(types: Vec<Type>, span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Tuple(types),
            span,
        })
    }

    pub fn newtype(tid: Tid, args: Vec<Type>, span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Newtype(tid, args),
            span,
        })
    }

    pub fn function(input: Type, output: Type, span: Span) -> Self {
        Type::App(App {
            kind: AppKind::Function(Box::new(input), Box::new(output)),
            span,
        })
    }

    pub fn is_function(&self) -> bool {
        matches!(
            self,
            Type::App(App {
                kind: AppKind::Function(_, _),
                ..
            })
        )
    }

    pub fn substitute(self, subst: &HashMap<Var, Type>) -> Self {
        match self {
            Type::Var(var) => subst.get(&var).cloned().unwrap_or(self),
            Type::App(app) => match app.kind {
                AppKind::Int | AppKind::Str | AppKind::Bool | AppKind::Unit => Type::App(app),

                AppKind::List(item) => Type::App(App {
                    kind: AppKind::List(Box::new(item.substitute(subst))),
                    span: app.span,
                }),

                AppKind::Tuple(fields) => {
                    let fields = fields.into_iter().map(|t| t.substitute(subst)).collect();

                    Type::App(App {
                        kind: AppKind::Tuple(fields),
                        span: app.span,
                    })
                }

                AppKind::Newtype(tid, generics) => {
                    let generics = generics.into_iter().map(|t| t.substitute(subst)).collect();

                    Type::App(App {
                        kind: AppKind::Newtype(tid, generics),
                        span: app.span,
                    })
                }

                AppKind::Function(input, output) => {
                    let input = input.substitute(subst);
                    let output = output.substitute(subst);

                    Type::App(App {
                        kind: AppKind::Function(Box::new(input), Box::new(output)),
                        span: app.span,
                    })
                }
            },
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct App {
    pub kind: AppKind,
    pub span: Span,
}

impl fmt::Display for App {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.kind.fmt(f)
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum AppKind {
    Int,
    Str,
    Bool,
    Unit,
    List(Box<Type>),
    Tuple(Vec<Type>),
    Newtype(Tid, Vec<Type>),
    Function(Box<Type>, Box<Type>),
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Type::Var(var) => write!(f, "'{}", var.index),
            Type::App(app) => write!(f, "{app}"),
        }
    }
}

impl fmt::Display for AppKind {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AppKind::Int => write!(f, "int"),
            AppKind::Str => write!(f, "str"),
            AppKind::Bool => write!(f, "bool"),
            AppKind::Unit => write!(f, "{{}}"),
            AppKind::List(ty) => write!(f, "[{ty}]"),

            AppKind::Tuple(types) => {
                let types: Vec<String> = types.iter().map(ToString::to_string).collect();
                write!(f, "{}", types.join(", "))
            }

            AppKind::Newtype(tid, generics) => {
                let generics: Vec<String> = generics.iter().map(ToString::to_string).collect();
                write!(f, "{} {}", tid, generics.join(" "))
            }

            AppKind::Function(input, output) => {
                write!(f, "{input} -> {output}")
            }
        }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Var {
    index: u64,
    span: Span,
}

impl Var {
    pub fn fresh(span: Span) -> Self {
        static NEXT_INDEX: AtomicU64 = AtomicU64::new(0);
        let index = NEXT_INDEX.fetch_add(1, Ordering::SeqCst);
        Var { index, span }
    }

    pub const fn span(&self) -> Span {
        self.span
    }

    pub const fn with_span(self, span: Span) -> Self {
        Self {
            index: self.index,
            span,
        }
    }
}

impl PartialEq for Var {
    fn eq(&self, other: &Self) -> bool {
        self.index == other.index
    }
}

impl Eq for Var {}

impl PartialOrd for Var {
    fn partial_cmp(&self, other: &Self) -> Option<cmp::Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for Var {
    fn cmp(&self, other: &Self) -> cmp::Ordering {
        self.index.cmp(&other.index)
    }
}

impl Hash for Var {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.index.hash(state);
    }
}
