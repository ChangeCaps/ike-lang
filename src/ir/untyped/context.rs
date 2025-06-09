use std::{
    collections::{HashMap, HashSet},
    ops::{Index, IndexMut},
};

use crate::diagnostic::{Diagnostic, Emitter, Span};

use super::{App, Type, Var};

#[derive(Debug)]
pub struct TypeError;

#[derive(Clone, Debug, PartialEq)]
pub struct TypeContext {
    newtypes: Vec<Newtype>,
    bounds: HashMap<Var, Bounds>,
    subst: HashMap<Var, Type>,
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

            Type::App(App::Newtype(tid, ref generics)) => {
                let newtype = &self[tid];

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

            Type::App(App::Int) => {}

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

                let fresh = Var::fresh();
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

            Type::App(app) => match app {
                App::Int | App::Bool | App::Str | App::Unit => {}

                App::List(element) => {
                    self.instantiate_impl(&mut *element, new_vars);
                }

                App::Tuple(fields) => {
                    for field in fields {
                        self.instantiate_impl(field, new_vars);
                    }
                }

                App::Newtype(_, generics) => {
                    for generic in generics {
                        self.instantiate_impl(generic, new_vars);
                    }
                }

                App::Function(input, output) => {
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
        match (lhs, rhs) {
            (App::Int, App::Int)
            | (App::Bool, App::Bool)
            | (App::Str, App::Str)
            | (App::Unit, App::Unit) => {}

            (App::List(lhs_element), App::List(rhs_element)) => {
                self.unify(*lhs_element, *rhs_element, span);
            }

            (App::Tuple(lhs_fields), App::Tuple(rhs_fields)) => {
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

            (App::Newtype(lhs_tid, lhs_generics), App::Newtype(rhs_tid, rhs_generics)) => {
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

            (App::Function(lhs_input, lhs_output), App::Function(rhs_input, rhs_output)) => {
                self.unify(*lhs_input, *rhs_input, span);
                self.unify(*lhs_output, *rhs_output, span);
            }

            (lhs, rhs) => {
                let diagnostic = Diagnostic::error(format!(
                    "cannot unify types: `{}` and `{}`",
                    self.format_type(&Type::App(lhs)),
                    self.format_type(&Type::App(rhs)),
                ))
                .with_label(span, "arising from here");

                self.errors.push(diagnostic);
            }
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

    pub fn substitute(&self, ty: Type) -> Type {
        match ty {
            Type::Var(var) => match self.subst.get(&var) {
                Some(subst_ty) => self.substitute(subst_ty.clone()),
                None => Type::Var(var),
            },

            Type::App(app) => match app {
                App::Int | App::Bool | App::Str | App::Unit => Type::App(app),

                App::List(mut element) => {
                    *element = self.substitute(*element);

                    Type::App(App::List(element))
                }

                App::Tuple(mut fields) => {
                    for field in &mut fields {
                        *field = self.substitute(field.clone());
                    }

                    Type::App(App::Tuple(fields))
                }

                App::Newtype(tid, mut generics) => {
                    for generic in &mut generics {
                        *generic = self.substitute(generic.clone());
                    }

                    Type::App(App::Newtype(tid, generics))
                }

                App::Function(mut input, mut output) => {
                    *input = self.substitute(*input);
                    *output = self.substitute(*output);

                    Type::App(App::Function(input, output))
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
            .map(|name| format!("'{}", name))
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
                format!("'{}: {}", name, bounds_str)
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

            Type::App(app) => match app {
                App::Int | App::Bool | App::Str | App::Unit => {}

                App::List(element) => {
                    self.enumerate_vars(element, vars);
                }

                App::Tuple(fields) => {
                    for field in fields {
                        self.enumerate_vars(field, vars);
                    }
                }

                App::Newtype(_, generics) => {
                    for generic in generics {
                        self.enumerate_vars(generic, vars);
                    }
                }

                App::Function(input, output) => {
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

            Type::App(app) => match app {
                App::Int => String::from("int"),
                App::Str => String::from("str"),
                App::Bool => String::from("bool"),
                App::Unit => String::from("{}"),

                App::List(element) => {
                    let element_str = self.format_type_impl(element, vars, 0);
                    format!("[{}]", element_str)
                }

                App::Tuple(fields) => {
                    let fields_str: Vec<String> = fields
                        .iter()
                        .map(|field| self.format_type_impl(field, vars, 1))
                        .collect();

                    fields_str.join(" * ")
                }

                App::Newtype(tid, generics) => {
                    let newtype = &self[*tid];

                    let generics = generics
                        .iter()
                        .map(|g| self.format_type_impl(g, vars, 0))
                        .collect::<Vec<String>>();

                    if generics.is_empty() {
                        return newtype.name.clone();
                    }

                    format!("{}<{}>", newtype.name, generics.join(", "))
                }

                App::Function(input, output) => {
                    let input_str = self.format_type_impl(input, vars, 1);
                    let output_str = self.format_type_impl(output, vars, 0);

                    let function = format!("{} -> {}", input_str, output_str);

                    if p > 0 {
                        format!("({})", function)
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
