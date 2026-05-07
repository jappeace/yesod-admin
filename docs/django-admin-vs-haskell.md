# Django Admin vs Haskell Frameworks: Investigation Report

## Executive Summary

Django's admin is the gold standard for auto-generated CRUD interfaces: one line
of code (`admin.site.register(Model)`) gives you a fully functional back-office
UI. The Haskell ecosystem has **nothing comparable**. IHP comes closest with
schema-driven code generation, but requires explicit scaffolding per entity.
Yesod has no usable admin solution — every attempt was abandoned by 2016. The
gap represents both a missing feature and an architectural challenge rooted in
how Haskell's type system handles runtime introspection.

---

## 1. How Django Does Admin Pages

### 1.1 Architecture

Django's admin is built on three core components:

- **AdminSite** — a singleton that owns a `_registry` mapping Model classes to
  ModelAdmin instances. Handles URL routing for the entire admin, manages
  site-wide settings, and can be subclassed for separate admin interfaces.
- **ModelAdmin** — the intermediary between a model and the admin UI. Controls
  list views, form generation, permissions, and actions. Initialized once at
  startup (not per-request).
- **ChangeList** — renders the list/overview page. Manages the pipeline:
  `get_queryset()` → filters → ordering → search.

**Autodiscovery**: when `django.contrib.admin` is in `INSTALLED_APPS`, Django
scans every app for an `admin.py` module, imports it, and all
`admin.site.register()` calls populate the registry.

**Required infrastructure**: auth, contenttypes, messages, sessions — the admin
depends on Django's permission system and session management.

### 1.2 Auto-Generation from Models

The key mechanism is **runtime model introspection** via Python's `_meta`
attribute. Every Django model exposes:

- All field definitions (name, type, constraints)
- Relationships (ForeignKey, ManyToMany)
- Verbose names, help text, choices
- Validation rules (blank, null, max_length, etc.)

Each model field maps to a form widget automatically:

| Model Field     | Widget          |
|-----------------|-----------------|
| CharField       | TextInput       |
| TextField       | Textarea        |
| BooleanField    | CheckboxInput   |
| DateTimeField   | DateTimeInput   |
| ForeignKey      | Select dropdown |
| ManyToManyField | SelectMultiple  |
| Field w/choices | Select dropdown |

Form fields inherit model metadata: `required` from `blank`, `label` from
`verbose_name`, `help_text`, `max_length`. This means model changes
automatically propagate to the admin UI with zero code changes.

### 1.3 Minimal Registration

```python
from django.contrib import admin
from myapp.models import Article

admin.site.register(Article)
```

This single line produces: list page with all articles, add/edit/delete forms
with correct widgets, change history tracking, and pagination.

### 1.4 Key Features

**list_display** — controls which columns appear in the list view. Supports
model fields, related fields via `__` notation, callable methods with
`@admin.display` decorator.

**search_fields** — adds a search box. Supports prefix modifiers: `^`
(startswith), `=` (exact), `@` (full-text).

**list_filter** — adds a filter sidebar. Custom filters via `SimpleListFilter`.

**Inline editing** — edit related objects (e.g. chapters of a book) on the
same page as the parent, using `TabularInline` or `StackedInline`.

**list_editable** — edit fields directly in the list view without opening
the detail page.

**Actions** — bulk operations on selected objects (publish, export CSV, etc.).

**Permissions** — four levels per model (view, add, change, delete) with
object-level granularity. Integrated with Django's auth framework.

### 1.5 Customization Depth

Django's admin has extraordinary extension points:

- **Fieldsets** — group fields into collapsible sections
- **Dynamic per-request behavior** — every attribute has a `get_*()` method
  that receives the request (e.g. `get_readonly_fields`, `get_queryset`,
  `get_list_display`)
- **Custom views** — inject custom URLs via `get_urls()`
- **Template overrides** — per-model or global, using block inheritance
- **Multiple AdminSites** — entirely separate admin interfaces with different
  models, permissions, and branding
- **Save/delete hooks** — `save_model()`, `save_related()`, `delete_model()`
- **Foreign key filtering** — `formfield_for_foreignkey()` to restrict dropdowns

### 1.6 Strengths

- **Zero-to-CRUD in one line** — unmatched by any framework in any language
- **Deep model introspection** — model changes propagate automatically
- **30+ attributes, ~50 overridable methods** on ModelAdmin
- **Battle-tested maturity** — core component since 2005, used by thousands of
  organizations for two decades
- **Inline editing** of related objects (non-trivial to build by hand)

### 1.7 Weaknesses

- **Not for end users** — Django's own docs say it is for "trusted internal
  users," not public-facing
- **Model-centric, not process-centric** — poor fit for multi-step workflows
  or wizards
- **ForeignKey performance trap** — default Select widget loads ALL related
  objects (catastrophic for large tables)
- **Tightly coupled to Django ORM** — cannot work with external APIs or
  non-Django data sources
- **Limited UI/UX flexibility** — server-rendered forms, adding rich
  client-side interactivity requires escaping the paradigm
- **No built-in 2FA or brute-force protection**
- **Complexity cliff** — simple customizations are trivial, but significantly
  non-standard behavior requires overriding many interacting methods

---

## 2. Haskell Framework Comparison

### 2.1 Yesod

**Status**: Actively maintained core (yesod 1.6.x, persistent 2.14+, 2025).
Admin/CRUD packages: **all dead**.

**No built-in admin**. Yesod's philosophy is "type-safe building blocks" rather
than "batteries-included admin." Developers manually compose Persistent +
yesod-form + isAuthorized.

**Typical CRUD pattern** (every entity requires this boilerplate):

```haskell
-- Model (via Persistent TH)
share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
Tutorial
    title Text
    content Text
    deriving Show
|]

-- Routes
/tutorials              TutorialsR  GET POST
/tutorials/#TutorialId  TutorialR   GET POST DELETE

-- Form
tutorialForm :: Maybe Tutorial -> AForm Handler Tutorial
tutorialForm mTutorial =
  Tutorial
    <$> areq textField "Title"   (tutorialTitle   <$> mTutorial)
    <*> areq textareaField "Content" (tutorialContent <$> mTutorial)

-- Handler (one of several required)
postTutorialsR :: Handler Html
postTutorialsR = do
    ((result, _), _) <- runFormPost $
        renderBootstrap3 BootstrapBasicForm (tutorialForm Nothing)
    case result of
        FormSuccess tutorial -> do
            _ <- runDB $ insert tutorial
            redirect TutorialsR
        _ -> redirect TutorialsR
```

**Failed admin attempts**:

| Package            | Last Update | Status    |
|--------------------|-------------|-----------|
| yesod-admin        | 2021        | Abandoned (never released) |
| yesod-crud         | May 2016    | Unmaintained, build failures |
| yesod-crud-persist | Apr 2016    | Unmaintained, build failures |
| lambdacms-core     | Jul 2015    | Unmaintained |

**Type safety helps**: route safety (broken links are compile errors), form
safety (`FormSuccess` gives a validated value), authorization pattern-matches on
route constructors.

**Type safety hinders**: no generic reflection over entities (the fundamental
reason auto-admin is hard), boilerplate per entity, subsite complexity far
exceeds Django's `admin.site.register()`.

**GSoC 2025 proposal** existed for auto-generated admin pages in Yesod — it
has not materialized into working code.

### 2.2 IHP (Integrated Haskell Platform)

**Status**: Actively maintained (v1.5.0, March 2026). 5,283 GitHub stars. Backed
by digitally induced (commercial company).

**Closest to Django in the Haskell world**, but with a fundamental difference:
IHP **scaffolds** CRUD (generates source files you own) rather than
**auto-generating** it at runtime.

**Schema-first approach** — the inverse of Django:

| Aspect          | Django                                   | IHP                                    |
|-----------------|------------------------------------------|----------------------------------------|
| Source of truth | Python model classes                     | PostgreSQL DDL (`Schema.sql`)          |
| Type generation | Manual Python class definition           | Automatic from SQL at compile time     |
| Migrations      | `makemigrations` / `migrate`             | Direct schema editing + "Migrate DB"   |
| DB features     | Abstracted through ORM                   | Full PostgreSQL access                 |
| Type safety     | Runtime only                             | Compile-time guaranteed                |

**Code generation**: From the web-based dev IDE (port 8001), you name a
controller and IHP generates:

- Controller data type with all CRUD actions (7 constructors)
- Route registration
- Controller implementation with handlers for index/show/new/create/edit/update/delete
- Four view files (Index, Show, New, Edit)

The generator is **schema-aware**: it reads `Schema.sql`, infers column types,
generates appropriate form field helpers, and suggests validation
(e.g. `nonEmpty` for non-null text, `isEmail` for email columns).

**Admin pattern**: IHP supports multiple applications within a project. You run
`new-application admin` to create a separate `Admin/` directory, then scaffold
CRUD controllers within it. Not automatic, but fast (minutes per entity).

**HSX templates**: Quasi-quoted HTML (`[hsx| ... |]`) that compiles to
BlazeHtml. Compile-time validation of tags, attributes, and type correctness.
XSS escaping by default.

**Key advantage over Django**: generated code is fully visible, editable, and
type-checked. Renaming a column in `Schema.sql` causes compiler errors
everywhere the old name is referenced.

**Key disadvantage vs Django**: you must explicitly scaffold each entity. No
"register and go" pattern.

### 2.3 Other Haskell Frameworks and Libraries

**Servant** — type-level API DSL. No admin or CRUD generation.
`servant-util-beam-pg` provides auto filter/sort/paginate but no UI.

**Scotty** — minimal Sinatra-like. Zero admin capabilities.

**Beam** — type-safe database library. No UI generation.

**Hyperbole** — server-side interactive HTML (inspired by HTMX/LiveView).
Actively maintained (v0.6.1, April 2026). Promising but no auto-generation.

**digestive-functors** / **reform** — form libraries, actively maintained, but
require manually composing every form field. No auto-derivation from types.

**generics-sop** — provides type-level metadata (constructor names, field names)
that *could* power auto-generated forms. Nobody has built this.

**regular-web** (2010) — the closest historical attempt at generic form
generation from Haskell types. Dead for 15+ years.

---

## 3. The Fundamental Gap

### Why Django Can Do This and Haskell Can't (Easily)

Django's admin works because Python enables **trivial runtime introspection**:

```python
for field in model._meta.fields:
    print(field.name, field.__class__.__name__, field.choices)
```

In Haskell, the equivalent requires either:

1. **Template Haskell** — generates code at compile time from model definitions
   (Persistent does this for DB ops, nobody has done it comprehensively for admin UIs)
2. **GHC Generics / generics-sop** — provides type-level metadata that can be
   walked generically. The infrastructure exists but no one has wired it to
   produce web forms + CRUD handlers
3. **Typeable / Data** — "Scrap Your Boilerplate" style. The abandoned
   `regular-web` (2010) used this approach

The technical barrier is not insurmountable — the pieces exist. The social
barrier is that the Haskell web ecosystem is small, and the few developers who
work in it tend to value explicit control over auto-generation.

### What Would a "Haskell Admin" Look Like?

A hypothetical solution could:

- Use `generics-sop` to walk record fields and produce form HTML
- Use Persistent's `EntityDef` metadata for DB field types and constraints
- Generate type-safe CRUD handlers via a typeclass (e.g. `AdminModel a`)
- Provide list views with sorting/filtering/pagination from field metadata
- Run on top of Servant or Yesod as a subsite

This is approximately what `yesod-admin` tried to build before being abandoned.
The challenge is handling the full matrix of field types, relationships, custom
widgets, permissions, and edge cases that Django's admin has refined over 20 years.

---

## 4. Comparative Summary

| Feature                     | Django           | IHP              | Yesod            |
|-----------------------------|------------------|------------------|------------------|
| Auto admin from models      | Yes (1 line)     | No (scaffold)    | No               |
| CRUD generation             | Automatic        | Code generator   | Manual           |
| Form generation             | From model meta  | Schema-aware     | Manual (AForm)   |
| Type safety                 | Runtime          | Compile-time     | Compile-time     |
| Schema source of truth      | Python classes   | SQL DDL          | Persistent TH    |
| Inline related editing      | Built-in         | Manual           | Manual           |
| Bulk actions                | Built-in         | Manual           | Manual           |
| Permission system           | Built-in (4-level) | Manual        | isAuthorized     |
| Search/filter/sort          | Declarative      | Manual           | Manual           |
| Customization ceiling       | ModelAdmin API   | Unlimited (code) | Unlimited (code) |
| Time to first CRUD          | Seconds          | Minutes          | Hours            |
| Active admin packages       | Core framework   | Scaffolding only | None (all dead)  |
| Maturity                    | 20+ years        | ~6 years         | ~14 years (no admin) |

---

## 5. Recommendations

### For the RAD Investigation Project

1. **Django's admin is the benchmark** — any Haskell solution should be measured
   against the "one line to CRUD" developer experience.

2. **IHP's approach is the most viable starting point** in the Haskell world —
   schema-driven code generation with compile-time safety. The trade-off
   (explicit scaffolding vs. automatic introspection) may be acceptable given
   the type-safety benefits.

3. **The missing piece is a `generics-sop`-based admin library** — something
   that walks Haskell record types and auto-generates:
   - List views with sortable/filterable columns
   - Create/edit forms with appropriate widgets per field type
   - Delete confirmation
   - Pagination
   - Basic permission checks

4. **Persistent's `EntityDef`** already contains the metadata needed (field
   names, types, constraints). A library that reads this metadata and produces
   admin pages would fill the Yesod ecosystem gap that has been empty since 2016.

5. **Don't replicate Django's weaknesses** — a Haskell admin should:
   - Handle ForeignKey fields efficiently from the start (no "load all rows" default)
   - Support process-centric workflows, not just table-centric CRUD
   - Provide compile-time guarantees that Django's runtime approach cannot

---

## Sources

- [Django Admin Documentation (6.0)](https://docs.djangoproject.com/en/6.0/ref/contrib/admin/)
- [Yesod Web Framework](https://www.yesodweb.com/)
- [IHP Documentation](https://ihp.digitallyinduced.com/Guide/)
- [IHP GitHub](https://github.com/digitallyinduced/ihp)
- [piyush-kurur/yesod-admin (Abandoned)](https://github.com/piyush-kurur/yesod-admin)
- [yesod-crud on Hackage](https://hackage.haskell.org/package/yesod-crud)
- [yesod-crud-persist on Hackage](https://hackage.haskell.org/package/yesod-crud-persist)
- [servant-util on Hackage](https://hackage.haskell.org/package/servant-util)
- [generics-sop on Hackage](https://hackage.haskell.org/package/generics-sop)
- [digestive-functors on Hackage](https://hackage.haskell.org/package/digestive-functors)
- [Hyperbole on Hackage](https://hackage.haskell.org/package/hyperbole)
- [regular-web on Hackage](https://hackage.haskell.org/package/regular-web)
- [Enhancing Yesod Capabilities — Haskell Discourse](https://discourse.haskell.org/t/enhancing-yesod-capabilities/11704)
- [Grace Browser — Generate Web Forms from Pure Functions](https://www.haskellforall.com/2022/05/generate-web-forms-from-pure-functions.html)
