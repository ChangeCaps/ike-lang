use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Sid(pub u64);

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Span {
    pub id: Sid,
    pub lo: u32,
    pub hi: u32,
}

impl Span {
    pub const fn new(id: Sid, lo: u32, hi: u32) -> Self {
        Self { id, lo, hi }
    }

    pub fn join(self, other: Self) -> Self {
        debug_assert_eq!(self.id, other.id, "Cannot join spans with different ids");

        Self {
            id: self.id,
            lo: self.lo.min(other.lo),
            hi: self.hi.max(other.hi),
        }
    }
}

impl fmt::Debug for Span {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}..{}", self.id.0, self.lo, self.hi)
    }
}
