use std::{
    fmt,
    ops::{Index, IndexMut},
    path::PathBuf,
};

#[derive(Clone, Debug, Default)]
pub struct Sources {
    sources: Vec<Source>,
}

impl Sources {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add(&mut self, source: Source) -> Sid {
        let index = self.sources.len();
        self.sources.push(source);
        Sid(index as u64)
    }
}

impl Index<Sid> for Sources {
    type Output = Source;

    fn index(&self, Sid(index): Sid) -> &Self::Output {
        &self.sources[index as usize]
    }
}

impl IndexMut<Sid> for Sources {
    fn index_mut(&mut self, Sid(index): Sid) -> &mut Self::Output {
        &mut self.sources[index as usize]
    }
}

#[derive(Clone, Debug)]
pub struct Source {
    pub path: PathBuf,
    pub content: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Sid(pub u64);

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct Span {
    pub id: Sid,
    pub lo: u32,
    pub hi: u32,
}

impl Span {
    pub const fn dummy() -> Self {
        Self {
            id: Sid(u64::MAX),
            lo: u32::MAX,
            hi: u32::MAX,
        }
    }

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

    pub fn compute_start_line_column(self, source: &str) -> (u32, u32) {
        let mut line = 1;
        let mut column = 1;
        let mut offset = 0;

        for c in source.chars() {
            if self.lo as usize <= offset {
                break;
            }

            match c {
                '\n' => {
                    line += 1;
                    column = 1;
                }

                _ => column += 1,
            }

            offset += c.len_utf8();
        }

        (line, column)
    }

    pub fn compute_end_line_column(self, source: &str) -> (u32, u32) {
        let mut line = 1;
        let mut column = 1;
        let mut offset = 0;

        for c in source.chars() {
            if self.hi as usize <= offset {
                break;
            }

            match c {
                '\n' => {
                    line += 1;
                    column = 1;
                }

                _ => column += 1,
            }

            offset += c.len_utf8();
        }

        (line, column)
    }
}

impl fmt::Debug for Span {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}..{}", self.id.0, self.lo, self.hi)
    }
}
