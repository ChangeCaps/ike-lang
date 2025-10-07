use crate::diagnostic::Span;

#[derive(Clone, Debug)]
pub struct Pattern {
    pub kind: PatternKind,
    pub span: Span,
}

#[derive(Clone, Debug)]
pub enum PatternKind {
    Wildcard,
    Binding(usize),
}

impl Pattern {
    pub fn is_refutable(&self) -> bool {
        match self.kind {
            PatternKind::Wildcard | PatternKind::Binding(_) => false,
        }
    }
}
