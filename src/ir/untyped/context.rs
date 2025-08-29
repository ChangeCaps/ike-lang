use std::{
    collections::{HashMap, HashSet},
    fmt,
    ops::{Index, IndexMut},
};

use crate::diagnostic::{Diagnostic, Emitter, Span};

use super::{App, AppKind, Type, Var};

#[derive(Debug)]
pub struct TypeError;

#[derive(Clone, Debug)]
pub struct TypeContext {
    newtypes: Vec<Newtype>,
    bounds: HashMap<Var, Bounds>,
    subst: HashMap<Var, Type>,
    cache: HashSet<(Type, Type)>,
    errors: Vec<Diagnostic>,
}

impl Default for TypeContext {
    fn default() -> Self {
        TypeContext::new()
    }
}

impl TypeContext {
    pub fn new() -> Self {
        TypeContext {
            newtypes: Vec::new(),
            bounds: HashMap::new(),
            subst: HashMap::new(),
            cache: HashSet::new(),
            errors: Vec::new(),
        }
    }

    pub fn push_newtype(&mut self, newtype: Newtype) -> Tid {
        let index = self.newtypes.len() as u64;
        self.newtypes.push(newtype);
        Tid { index }
    }

    pub fn bounds_mut(&mut self, var: Var) -> &mut Bounds {
        self.bounds.entry(var).or_default()
    }

    pub fn finish(&mut self, emitter: &mut dyn Emitter) -> Result<(), TypeError> {
        if self.errors.is_empty() {
            return Ok(());
        }

        for error in self.errors.drain(..) {
            emitter.emit(error);
        }

        Err(TypeError)
    }

    pub fn field(&mut self, target: Type, name: &str, ty: Type, span: Span) {
        if let Some(subst_ty) = self.substitute_shallow(&target) {
            return self.field(subst_ty, name, ty, span);
        }

        match target {
            Type::Var(var) => {
                let bounds = self.bounds_mut(var);

                match bounds.fields.get(name).cloned() {
                    Some(existing) => {
                        self.unify(existing, ty, span);
                    }

                    None => {
                        bounds.fields.insert(name.to_string(), ty);
                    }
                }
            }

            Type::App(App {
                kind: AppKind::Newtype(tid, ref generics),
                ..
            }) => {
                let newtype = &self[tid];

                if let NewtypeKind::Alias(ref alias) = newtype.kind {
                    return self.field(alias.clone(), name, ty, span);
                }

                let NewtypeKind::Record(record) = &newtype.kind else {
                    let diagnostic = Diagnostic::error(format!(
                        "type `{}` does not support fields",
                        self.format_type(&target),
                    ))
                    .with_label(span, "arising from here");

                    self.errors.push(diagnostic);
                    return;
                };

                let Some(field) = record.field(name) else {
                    let diagnostic = Diagnostic::error(format!(
                        "type `{}` does not have a field named `{}`",
                        self.format_type(&target),
                        name,
                    ))
                    .with_label(span, "arising from here");

                    self.errors.push(diagnostic);
                    return;
                };

                let subst = newtype
                    .generics
                    .iter()
                    .map(|(_, var)| *var)
                    .zip(generics.iter().cloned())
                    .collect::<HashMap<_, _>>();

                let field_ty = field.ty.clone().substitute(&subst);
                self.unify(ty, field_ty, span);
            }

            Type::App(_) => {
                let diagnostic = Diagnostic::error(format!(
                    "type `{}` does not support fields",
                    self.format_type(&target),
                ))
                .with_label(span, "arising from here");

                self.errors.push(diagnostic);
            }
        }
    }

    pub fn number(&mut self, target: Type, span: Span) {
        if let Some(subst_ty) = self.substitute_shallow(&target) {
            return self.number(subst_ty, span);
        }

        match target {
            Type::Var(var) => {
                let bounds = self.bounds_mut(var);
                bounds.number = true;
            }

            Type::App(App {
                kind: AppKind::Int, ..
            }) => {}

            Type::App(_) => {
                let diagnostic = Diagnostic::error(format!(
                    "type `{}` is not a number",
                    self.format_type(&target),
                ))
                .with_label(span, "arising from here");

                self.errors.push(diagnostic);
            }
        }
    }

    pub fn instantiate(&mut self, mut ty: Type) -> Type {
        self.instantiate_impl(&mut ty, &mut HashMap::new());
        ty
    }

    fn instantiate_impl(&mut self, ty: &mut Type, new_vars: &mut HashMap<Var, Var>) {
        *ty = self.substitute(ty.clone());

        match ty {
            Type::Var(var) => {
                if let Some(new_var) = new_vars.get(var) {
                    *var = *new_var;
                    return;
                }

                let fresh = Var::fresh(var.span());
                new_vars.insert(*var, fresh);

                if let Some(bounds) = self.bounds.get(var).cloned() {
                    let mut new_bounds = Bounds {
                        number: bounds.number,
                        ..Default::default()
                    };

                    for (name, field_ty) in bounds.fields {
                        let mut field_ty = field_ty;
                        self.instantiate_impl(&mut field_ty, new_vars);
                        new_bounds.fields.insert(name, field_ty);
                    }

                    self.bounds.insert(fresh, new_bounds);
                }

                *var = fresh;
            }

            Type::App(app) => match app.kind {
                AppKind::Int | AppKind::Bool | AppKind::Str | AppKind::Unit => {}

                AppKind::List(ref mut element) => {
                    self.instantiate_impl(&mut *element, new_vars);
                }

                AppKind::Tuple(ref mut fields) => {
                    for field in fields {
                        self.instantiate_impl(field, new_vars);
                    }
                }

                AppKind::Newtype(_, ref mut generics) => {
                    for generic in generics {
                        self.instantiate_impl(generic, new_vars);
                    }
                }

                AppKind::Function(ref mut input, ref mut output) => {
                    self.instantiate_impl(&mut *input, new_vars);
                    self.instantiate_impl(&mut *output, new_vars);
                }
            },
        }
    }

    pub fn unify(&mut self, lhs: Type, rhs: Type, span: Span) {
        if let Some(lhs) = self.substitute_shallow(&lhs) {
            return self.unify(lhs, rhs, span);
        } else if let Some(rhs) = self.substitute_shallow(&rhs) {
            return self.unify(lhs, rhs, span);
        }

        if self.cache.contains(&(lhs.clone(), rhs.clone())) {
            return;
        }

        self.cache.insert((lhs.clone(), rhs.clone()));

        if lhs == rhs {
            return;
        }

        match (lhs, rhs) {
            (Type::Var(var), ty) | (ty, Type::Var(var)) => self.unify_var_ty(var, ty, span),
            (Type::App(lhs), Type::App(rhs)) => self.unify_app_app(lhs, rhs, span),
        }
    }

    fn unify_var_ty(&mut self, var: Var, ty: Type, span: Span) {
        if let Some(bounds) = self.bounds.get(&var).cloned() {
            if bounds.number {
                self.number(ty.clone(), span);
            }

            for (field_name, field_ty) in bounds.fields {
                self.field(ty.clone(), &field_name, field_ty, span);
            }
        }

        self.subst.insert(var, ty);
    }

    fn unify_app_app(&mut self, lhs: App, rhs: App, span: Span) {
        if let Some(lhs) = self.substitute_alias(&lhs) {
            return self.unify(lhs, Type::App(rhs), span);
        } else if let Some(rhs) = self.substitute_alias(&rhs) {
            return self.unify(Type::App(lhs), rhs, span);
        }

        match (lhs.kind, rhs.kind) {
            (AppKind::Int, AppKind::Int)
            | (AppKind::Bool, AppKind::Bool)
            | (AppKind::Str, AppKind::Str)
            | (AppKind::Unit, AppKind::Unit) => {}

            (AppKind::List(lhs_element), AppKind::List(rhs_element)) => {
                self.unify(*lhs_element, *rhs_element, span);
            }

            (AppKind::Tuple(lhs_fields), AppKind::Tuple(rhs_fields)) => {
                if lhs_fields.len() != rhs_fields.len() {
                    let diagnostic = Diagnostic::error(format!(
                        "cannot unify tuple types with different lengths: `{}` and `{}`",
                        lhs_fields.len(),
                        rhs_fields.len()
                    ))
                    .with_label(span, "arising from here");

                    self.errors.push(diagnostic);
                    return;
                }

                for (lhs_field, rhs_field) in lhs_fields.into_iter().zip(rhs_fields) {
                    self.unify(lhs_field, rhs_field, span);
                }
            }

            (AppKind::Newtype(lhs_tid, lhs_generics), AppKind::Newtype(rhs_tid, rhs_generics)) => {
                if lhs_tid != rhs_tid {
                    let message = format!(
                        "cannot unify newtypes: `{}` and `{}`",
                        self[lhs_tid].name, self[rhs_tid].name
                    );
                    let diagnostic =
                        Diagnostic::error(message).with_label(span, "arising from here");

                    self.errors.push(diagnostic);
                    return;
                }

                assert_eq!(lhs_generics.len(), rhs_generics.len());

                for (lhs_generic, rhs_generic) in lhs_generics.into_iter().zip(rhs_generics) {
                    self.unify(lhs_generic, rhs_generic, span);
                }
            }

            (
                AppKind::Function(lhs_input, lhs_output),
                AppKind::Function(rhs_input, rhs_output),
            ) => {
                self.unify(*lhs_input, *rhs_input, span);
                self.unify(*lhs_output, *rhs_output, span);
            }

            (lhs_kind, rhs_kind) => {
                let lhs_ty = self.format_type(&Type::App(App {
                    kind: lhs_kind,
                    span: lhs.span,
                }));

                let rhs_ty = self.format_type(&Type::App(App {
                    kind: rhs_kind,
                    span: rhs.span,
                }));

                let diagnostic =
                    Diagnostic::error(format!("cannot unify types: `{lhs_ty}` and `{rhs_ty}`",))
                        .with_label(span, "constraint arising from here")
                        .with_label(lhs.span, format!("`{lhs_ty}` here"))
                        .with_label(rhs.span, format!("`{rhs_ty}` here"));

                self.errors.push(diagnostic);
            }
        }
    }

    fn substitute_alias(&self, app: &App) -> Option<Type> {
        match app.kind {
            AppKind::Newtype(tid, ref generics) => {
                let newtype = &self[tid];

                match newtype.kind {
                    NewtypeKind::Alias(ref aliased) => {
                        let map = newtype
                            .generics
                            .iter()
                            .map(|(_, v)| *v)
                            .zip(generics.iter().cloned())
                            .collect();

                        Some(aliased.clone().substitute(&map))
                    }

                    _ => None,
                }
            }

            _ => None,
        }
    }

    fn substitute_shallow(&self, ty: &Type) -> Option<Type> {
        if let Type::Var(var) = ty {
            if let Some(subst_ty) = self.subst.get(var) {
                return Some(subst_ty.clone());
            }
        }

        None
    }

    /// Deeply substitute a type using the substitution table within the context.
    ///
    /// This will compute the most concrete type currently possible.
    pub fn substitute(&self, ty: Type) -> Type {
        match ty {
            Type::Var(var) => match self.subst.get(&var) {
                Some(subst_ty) => self.substitute(subst_ty.clone()),
                None => Type::Var(var),
            },

            Type::App(app) => match app.kind {
                AppKind::Int | AppKind::Bool | AppKind::Str | AppKind::Unit => Type::App(app),

                AppKind::List(mut element) => {
                    *element = self.substitute(*element);

                    Type::App(App {
                        kind: AppKind::List(element),
                        span: app.span,
                    })
                }

                AppKind::Tuple(mut fields) => {
                    for field in &mut fields {
                        *field = self.substitute(field.clone());
                    }

                    Type::App(App {
                        kind: AppKind::Tuple(fields),
                        span: app.span,
                    })
                }

                AppKind::Newtype(tid, mut generics) => {
                    for generic in &mut generics {
                        *generic = self.substitute(generic.clone());
                    }

                    Type::App(App {
                        kind: AppKind::Newtype(tid, generics),
                        span: app.span,
                    })
                }

                AppKind::Function(mut input, mut output) => {
                    *input = self.substitute(*input);
                    *output = self.substitute(*output);

                    Type::App(App {
                        kind: AppKind::Function(input, output),
                        span: app.span,
                    })
                }
            },
        }
    }

    pub fn format_type(&self, ty: &Type) -> String {
        let mut vars = HashSet::new();
        self.enumerate_vars(ty, &mut vars);

        let mut var_names = HashMap::new();
        for (i, var) in vars.into_iter().enumerate() {
            var_names.insert(var, Self::generate_var_name(i));
        }

        if var_names.is_empty() {
            return self.format_type_impl(ty, &var_names, 0);
        }

        let forall = var_names
            .values()
            .map(|name| format!("'{name}"))
            .collect::<Vec<_>>()
            .join(" ");

        let bounds = var_names
            .iter()
            .filter_map(|(var, name)| {
                self.bounds
                    .get(var)
                    .map(|bounds| (name.clone(), bounds.clone()))
            })
            .map(|(name, bounds)| {
                let bounds_str = self.format_bounds(&bounds, &var_names);
                format!("'{name}: {bounds_str}")
            })
            .collect::<Vec<_>>();

        let where_clause = if bounds.is_empty() {
            String::new()
        } else {
            format!(" where {}", bounds.join(", "))
        };

        format!(
            "forall {}. {}{}",
            forall,
            self.format_type_impl(ty, &var_names, 0),
            where_clause,
        )
    }

    fn format_bounds(&self, bounds: &Bounds, var_names: &HashMap<Var, String>) -> String {
        let mut parts = Vec::new();

        if bounds.number {
            parts.push("number".to_string());
        }

        for (name, field_ty) in &bounds.fields {
            let field_str = format!(
                ".{} = {}",
                name,
                self.format_type_impl(field_ty, var_names, 0),
            );
            parts.push(field_str);
        }

        parts.join(" + ")
    }

    fn enumerate_vars(&self, ty: &Type, vars: &mut HashSet<Var>) {
        if let Some(subst_ty) = self.substitute_shallow(ty) {
            return self.enumerate_vars(&subst_ty, vars);
        }

        match ty {
            Type::Var(var) => {
                vars.insert(*var);

                if let Some(bounds) = self.bounds.get(var) {
                    for field_ty in bounds.fields.values() {
                        self.enumerate_vars(field_ty, vars);
                    }
                }
            }

            Type::App(app) => match app.kind {
                AppKind::Int | AppKind::Bool | AppKind::Str | AppKind::Unit => {}

                AppKind::List(ref element) => {
                    self.enumerate_vars(element, vars);
                }

                AppKind::Tuple(ref fields) => {
                    for field in fields {
                        self.enumerate_vars(field, vars);
                    }
                }

                AppKind::Newtype(_, ref generics) => {
                    for generic in generics {
                        self.enumerate_vars(generic, vars);
                    }
                }

                AppKind::Function(ref input, ref output) => {
                    self.enumerate_vars(input, vars);
                    self.enumerate_vars(output, vars);
                }
            },
        }
    }

    fn format_type_impl(&self, ty: &Type, vars: &HashMap<Var, String>, p: u8) -> String {
        if let Some(subst_ty) = self.substitute_shallow(ty) {
            return self.format_type_impl(&subst_ty, vars, p);
        }

        match ty {
            Type::Var(var) => format!("'{}", vars[var]),

            Type::App(app) => match app.kind {
                AppKind::Int => String::from("int"),
                AppKind::Str => String::from("str"),
                AppKind::Bool => String::from("bool"),
                AppKind::Unit => String::from("{}"),

                AppKind::List(ref element) => {
                    let element_str = self.format_type_impl(element, vars, 0);
                    format!("[{element_str}]")
                }

                AppKind::Tuple(ref fields) => {
                    let fields_str: Vec<String> = fields
                        .iter()
                        .map(|field| self.format_type_impl(field, vars, 1))
                        .collect();

                    fields_str.join(", ")
                }

                AppKind::Newtype(tid, ref generics) => {
                    let newtype = &self[tid];

                    let generics = generics
                        .iter()
                        .map(|g| self.format_type_impl(g, vars, 1))
                        .collect::<Vec<String>>();

                    if generics.is_empty() {
                        return newtype.name.clone();
                    }

                    format!("{} {}", newtype.name, generics.join(" "))
                }

                AppKind::Function(ref input, ref output) => {
                    let input_str = self.format_type_impl(input, vars, 1);
                    let output_str = self.format_type_impl(output, vars, 0);

                    let function = format!("{input_str} -> {output_str}");

                    if p > 0 {
                        format!("({function})")
                    } else {
                        function
                    }
                }
            },
        }
    }

    fn generate_var_name(index: usize) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyz";

        let mut name = String::new();
        let mut i = index + 1;

        while i > 0 {
            let letter_index = (i - 1) % letters.len();
            name.push(letters.chars().nth(letter_index).unwrap());
            i = (i - 1) / letters.len();
        }

        name.chars().rev().collect()
    }
}

impl Index<Tid> for TypeContext {
    type Output = Newtype;

    fn index(&self, tid: Tid) -> &Self::Output {
        &self.newtypes[tid.index as usize]
    }
}

impl IndexMut<Tid> for TypeContext {
    fn index_mut(&mut self, tid: Tid) -> &mut Self::Output {
        &mut self.newtypes[tid.index as usize]
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Bounds {
    pub number: bool,
    pub fields: HashMap<String, Type>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub struct Tid {
    index: u64,
}

impl fmt::Display for Tid {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "t{}", self.index)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Newtype {
    pub name: String,
    pub generics: Vec<(String, Var)>,
    pub kind: NewtypeKind,
}

#[derive(Clone, Debug, PartialEq)]
pub enum NewtypeKind {
    Record(Record),
    Union(Union),
    Alias(Type),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Record {
    pub fields: Vec<Field>,
}

impl Record {
    pub fn field(&self, name: &str) -> Option<&Field> {
        self.fields.iter().find(|f| f.name == name)
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Field {
    pub name: String,
    pub ty: Type,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Union {
    pub variants: Vec<Variant>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Variant {
    pub name: String,
    pub ty: Option<Type>,
}
