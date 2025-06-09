use std::{
    collections::HashMap,
    fmt,
    sync::atomic::{AtomicU64, Ordering},
};

use super::Tid;

#[derive(Clone, Debug, PartialEq)]
pub enum Type {
    Var(Var),
    App(App),
}

impl Type {
    pub fn infer() -> Self {
        Type::Var(Var::fresh())
    }

    pub const fn int() -> Self {
        Type::App(App::Int)
    }

    pub const fn str() -> Self {
        Type::App(App::Str)
    }

    pub const fn bool() -> Self {
        Type::App(App::Bool)
    }

    pub const fn unit() -> Self {
        Type::App(App::Unit)
    }

    pub fn list(ty: Type) -> Self {
        Type::App(App::List(Box::new(ty)))
    }

    pub fn tuple(types: Vec<Type>) -> Self {
        Type::App(App::Tuple(types))
    }

    pub fn newtype(tid: Tid, args: Vec<Type>) -> Self {
        Type::App(App::Newtype(tid, args))
    }

    pub fn function(input: Type, output: Type) -> Self {
        Type::App(App::Function(Box::new(input), Box::new(output)))
    }

    pub fn is_function(&self) -> bool {
        matches!(self, Type::App(App::Function(_, _)))
    }

    pub fn substitute(self, subst: &HashMap<Var, Type>) -> Self {
        match self {
            Type::Var(var) => subst.get(&var).cloned().unwrap_or(self),
            Type::App(app) => match app {
                App::Int | App::Str | App::Bool | App::Unit => Type::App(app),

                App::List(item) => Type::App(App::List(Box::new(item.substitute(subst)))),

                App::Tuple(fields) => {
                    let fields = fields.into_iter().map(|t| t.substitute(subst)).collect();

                    Type::App(App::Tuple(fields))
                }

                App::Newtype(tid, generics) => {
                    let generics = generics.into_iter().map(|t| t.substitute(subst)).collect();

                    Type::App(App::Newtype(tid, generics))
                }

                App::Function(input, output) => {
                    let input = input.substitute(subst);
                    let output = output.substitute(subst);

                    Type::App(App::Function(Box::new(input), Box::new(output)))
                }
            },
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub enum App {
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
            Type::Var(_) => write!(f, "_"),
            Type::App(app) => write!(f, "{}", app),
        }
    }
}

impl fmt::Display for App {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            App::Int => write!(f, "int"),
            App::Str => write!(f, "str"),
            App::Bool => write!(f, "bool"),
            App::Unit => write!(f, "{{}}"),
            App::List(ty) => write!(f, "[{}]", ty),

            App::Tuple(types) => {
                let types: Vec<String> = types.iter().map(ToString::to_string).collect();
                write!(f, "{}", types.join(", "))
            }

            App::Newtype(tid, generics) => {
                let generics: Vec<String> = generics.iter().map(ToString::to_string).collect();
                write!(f, "{:?}<{}>", tid, generics.join(", "))
            }

            App::Function(input, output) => {
                write!(f, "{} -> {}", input, output)
            }
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Var {
    index: u64,
}

impl Var {
    pub fn fresh() -> Self {
        static NEXT_INDEX: AtomicU64 = AtomicU64::new(0);
        let index = NEXT_INDEX.fetch_add(1, Ordering::SeqCst);
        Var { index }
    }
}
