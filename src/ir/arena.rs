macro_rules! impl_arena {
    ($arena:ident, $item:ty, $id:ident) => {
        #[derive(::std::clone::Clone, ::std::fmt::Debug, ::std::cmp::PartialEq)]
        pub struct $arena<T> {
            items: Vec<$item>,
        }

        impl<T> ::std::default::Default for $arena<T> {
            fn default() -> Self {
                Self::new()
            }
        }

        impl<T> $arena<T> {
            pub fn new() -> Self {
                Self { items: Vec::new() }
            }

            pub fn push(&mut self, item: $item) -> $id<T> {
                let index = self.items.len();
                self.items.push(item);
                $id {
                    index,
                    marker: PhantomData,
                }
            }

            pub fn iter(&self) -> impl ::std::iter::ExactSizeIterator<Item = ($id<T>, &$item)> + ::std::iter::DoubleEndedIterator {
                self.items.iter().enumerate().map(|(index, item)| {
                    let id = $id {
                        index,
                        marker: PhantomData,
                    };

                    (id, item)
                })
            }

            pub fn values(&self) -> impl ::std::iter::ExactSizeIterator<Item = &$item> + ::std::iter::DoubleEndedIterator  {
                self.items.iter()
            }

            pub fn keys(&self) -> impl ::std::iter::ExactSizeIterator<Item = $id<T>> + ::std::iter::DoubleEndedIterator + use<T> {
                (0..self.items.len()).map(|index| $id {
                    index,
                    marker: PhantomData,
                })
            }
        }

        impl<T> ::std::ops::Index<$id<T>> for $arena<T> {
            type Output = $item;

            fn index(&self, index: $id<T>) -> &Self::Output {
                &self.items[index.index]
            }
        }

        impl<T> ::std::ops::IndexMut<$id<T>> for $arena<T> {
            fn index_mut(&mut self, index: $id<T>) -> &mut Self::Output {
                &mut self.items[index.index]
            }
        }

        pub struct $id<T> {
            index: usize,
            marker: ::std::marker::PhantomData<fn() -> T>,
        }

        impl<T> $id<T> {
            pub fn cast<U>(self) -> $id<U> {
                $id {
                    index: self.index,
                    marker: ::std::marker::PhantomData,
                }
            }

            pub fn index(&self) -> usize {
                self.index
            }
        }

        impl<T> ::std::clone::Clone for $id<T> {
            fn clone(&self) -> Self {
                *self
            }
        }

        impl<T> ::std::marker::Copy for $id<T> {}

        impl<T> ::std::fmt::Debug for $id<T> {
            fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> ::std::fmt::Result {
                write!(f, "{}({})", stringify!($id), self.index)
            }
        }

        impl<T> ::std::cmp::PartialEq for $id<T> {
            fn eq(&self, other: &Self) -> bool {
                self.index == other.index
            }
        }

        impl<T> ::std::cmp::Eq for $id<T> {}

        impl<T> ::std::hash::Hash for $id<T> {
            fn hash<H: ::std::hash::Hasher>(&self, state: &mut H) {
                ::std::hash::Hash::hash(&self.index, state);
            }
        }
    };
}

pub(super) use impl_arena;
