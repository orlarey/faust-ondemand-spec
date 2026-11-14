---
title: Un calcul d'horloges pour Faust
subtitle: Spécification, brouillon v12
date: 14 novembre 2026
document-style: article-a4
language: fr
---

::: toc+
- **Objet et statut** — dire ce que le document spécifie et où en est le travail.
- **Les repères temporels** — construire le temps sur ℕ, sans parler de signaux.
  - **Le temps d'une horloge** — une succession d'instants numérotés.
  - **Un repère et son parent** — la cadence et la remontée.
  - **Sélection et subdivision** — les deux cas remarquables.
  - **La hiérarchie** — une horloge est la suite des cadences qui y mènent.
  - **Les horloges données par l'hôte** — initialisation, blocs, échantillons.
- **Les signaux** — poser les valeurs sur les repères.
  - **Un signal et son horloge** — une valeur par instant.
  - **Voir un signal depuis un repère descendant** — composer avec la remontée.
  - **Sortir un signal vers le repère parent** — la seule opération du calcul.
  - **La cadence est un signal** — refermer la boucle entre horloges et signaux.
  - **Les trois primitives du langage** — ondemand, upsampling, downsampling.
- **Les opérations** — dire quelle horloge a le résultat d'une opération.
  - **Trois sortes d'opérations** — sans mémoire, à horloge, sortie.
  - **Règles d'horloge** — les règles d'inférence.
  - **Règles de valeur** — ce que la sortie fait aux intervalles.
- **La traduction des régions** — une traduction uniforme pour les trois primitives.
- **Lois** — les égalités que le compilateur peut appliquer.
- **Exemples** — le calcul déroulé à la main sur six programmes.
- **Parenté avec les langages synchrones** — ce qui est repris, ce qui diffère.
- **La place dans l'approche algébrique** — l'horloge dans la signature.
  - **L'horloge dans la signature** — un opérande, pas une donnée.
  - **Les deux formes** — forme normale et forme de calcul.
  - **Le point fixe** — la graine des variables récursives.
- **Où le code est exécuté** — horloge d'un signal et horloge d'exécution.
- **État de l'implémentation** — ce qui existe, sans effet sur le code généré.
- **Décisions et questions** — ce qui est pris, en attente, ouvert.
:::

# Objet et statut

Ce document pose la théorie des horloges qui servira de base à `ondemand`, `upsampling` et `downsampling` sur la lignée `master-dev-certification`.

Décision du 13 novembre : on spécifie, on n'implémente pas. L'implémentation ne commencera qu'après la bascule de `master-dev` sur la branche de certification. Le but de la spécification est d'être simple, régulière, et de proposer les bonnes abstractions.

L'idée directrice de cette version : il n'y a pas de temps global. Chaque horloge est un **repère temporel** dont le temps est simplement ℕ, et les repères forment une hiérarchie. On passe d'un repère à son parent par une fonction, la remontée. Cette lecture est une proposition, à confirmer.

Les marques **[D]** signalent une décision prise, **[P]** une proposition, **[Q]** une question.

Sources : `spec.md` (ondemand v5), les documents Expressive E, les slides IFC-24, et dans `faust-migration` : `FAUSTALGEBRA.md`, `LES-ALGEBRES-DE-TRANSFORMATION.md`, `ATTRIBUTES.md`, `FIXPOINT-SPEC.md`, `LA-FORME-DE-CALCUL.md`.

# Les repères temporels

Cette section ne parle que du temps. Les signaux n'arrivent qu'à la section suivante. Tout y est construit sur ℕ.

## Le temps d'une horloge

::: definition [Instant]
Le temps d'une horloge est ℕ. Un **instant** est un entier : 0 est le premier instant, 1 le deuxième, etc.
:::

Chaque horloge a son propre temps. L'instant 5 d'une horloge et l'instant 5 d'une autre n'ont a priori aucun rapport : pour les relier, il faut passer par la hiérarchie.

## Un repère et son parent

Une horloge se construit à partir d'une autre, son **parent**, en disant combien de ses instants ont lieu pendant chaque instant du parent.

::: definition [Cadence]
Une **cadence** est une fonction r : ℕ → ℕ. r(t) est le nombre d'instants de la nouvelle horloge qui ont lieu pendant l'instant t du parent.
:::

Le nombre d'instants de la nouvelle horloge qui ont eu lieu avant l'instant t du parent est

```math
\mathit{avant}(t) = r(0) + r(1) + … + r(t - 1)
```

Pendant l'instant t du parent ont donc lieu les instants numérotés avant(t), avant(t) + 1, …, avant(t) + r(t) − 1 de la nouvelle horloge.

::: definition [Remontée]
La **remontée** π : ℕ → ℕ associe à chaque instant n de la nouvelle horloge l'instant du parent pendant lequel il a lieu : π(n) est l'unique t tel que avant(t) ≤ n < avant(t) + r(t).
:::

La remontée est croissante. La cadence et la remontée disent la même chose : r(t) est le nombre d'instants n tels que π(n) = t.

Un exemple, avec la cadence 1, 0, 3, 1 :

```
instant du parent   t   :   0     1     2           3
cadence           r(t)  :   1     0     3           1
avant(t)                :   0     1     1           4
instants de l'horloge n :   0           1  2  3     4
remontée          π(n)  :   0           2  2  2     3
```

Pendant l'instant 1 du parent il ne se passe rien. Pendant l'instant 2 ont lieu trois instants de la nouvelle horloge.

Si la cadence est nulle à partir d'un certain instant, la nouvelle horloge n'a qu'un nombre fini d'instants : son temps est un début de ℕ.

## Sélection et subdivision

Deux cas sont remarquables.

Sélection
:   r ne vaut jamais plus de 1. Il n'y a jamais deux instants pendant le même instant du parent : la remontée est strictement croissante.

Subdivision
:   r vaut toujours au moins 1. Il se passe quelque chose pendant chaque instant du parent : la remontée atteint tous les instants du parent.

Dans l'exemple ci-dessus, la cadence n'est ni l'une ni l'autre.

## La hiérarchie

Une horloge dérivée a un parent, qui peut lui-même en avoir un. En remontant on finit par atteindre une horloge sans parent, la **racine**.

::: definition [Horloge]
Une **horloge** est la suite des cadences qui y mènent depuis la racine : c = (r₁, r₂, …, rₖ). La racine est la suite vide (). Le **parent** de (r₁, …, rₖ) est (r₁, …, rₖ₋₁), et rₖ est une cadence sur le temps de ce parent.
:::

On note c · r l'horloge obtenue en ajoutant la cadence r à c.

Les **ancêtres** d'une horloge sont ses préfixes, elle-même comprise. On note a ≤ c quand a est un ancêtre de c. Les ancêtres d'une horloge sont rangés par longueur : ils forment une chaîne, de la racine jusqu'à elle.

Pour remonter d'une horloge c à l'un de ses ancêtres a, on compose les remontées successives. On note π(c → a) cette remontée composée ; π(c → c) est l'identité.

Deux horloges qui ne sont pas ancêtres l'une de l'autre n'ont de rapport que par leur plus long préfixe commun.

## Les horloges données par l'hôte

**[P]** Trois horloges sont données par l'hôte. Elles forment le début de toute hiérarchie.

| Horloge | Suite | Son temps | Cadence qui y mène |
| :--- | :--- | :--- | :--- |
| initialisation | () | un seul instant, 0 | aucune : c'est la racine |
| blocs **B** | (ω) | un instant par appel de `compute` | tous les blocs ont lieu pendant l'unique instant de la racine |
| échantillons **S** | (ω, count) | un instant par échantillon | count(k) est la longueur du bloc k |

La remontée de **S** vers **B** associe à chaque numéro d'échantillon le numéro de son bloc. Avec des blocs de 64 échantillons, π(n) = n div 64.

La racine n'a qu'un instant. C'est la seule horloge dont la cadence d'accès n'est pas un entier : ω dit que les blocs se succèdent sans fin pendant cet unique instant.

Le remplissage d'une table de taille n se fait sur une autre fille de la racine, l'horloge (n), qui a n instants.

# Les signaux

## Un signal et son horloge

::: definition [Signal]
Un **signal** d'horloge c est une fonction qui donne une valeur réelle à chaque instant de c.
:::

- Une constante est un signal de la racine : une seule valeur, à l'unique instant.
- Un slider est un signal d'horloge **B** : une valeur par bloc.
- Une entrée audio est un signal d'horloge **S** : une valeur par échantillon.

## Voir un signal depuis un repère descendant

Un signal est visible dans tous les repères qui descendent du sien : il suffit de remonter.

::: definition [Vue]
Soit x un signal d'horloge a, et c une horloge dont a est un ancêtre. La **vue** de x depuis c est le signal d'horloge c qui vaut, à l'instant n,

```math
x(π(c → a)(n))
```
:::

C'est une simple composition. Elle ne demande aucune opération dans le programme :

- une constante, vue de n'importe où, vaut toujours la même chose ;
- un slider vu de **S** garde la valeur de son bloc pendant tous les échantillons du bloc ;
- une entrée audio vue d'un `ondemand` y prend la valeur qu'elle a aux échantillons où la demande est faite.

Depuis une subdivision, on voit toutes les valeurs du signal, chacune répétée. Depuis une sélection, on ne voit que certaines d'entre elles.

## Sortir un signal vers le repère parent

Dans l'autre sens, il n'y a pas de fonction : pendant un instant du parent, une horloge peut avoir plusieurs instants, ou aucun. Sortir un signal demande donc de choisir une valeur. C'est la seule opération du calcul.

::: definition [Sortie]
Soit c = p · r, et y un signal visible depuis c. La **sortie** `Up(c, y)` est le signal d'horloge p qui vaut, à l'instant t de p :

- la valeur de y au **premier** instant de c pendant t, si r(t) ≥ 1 : y(avant(t)) ;
- sinon la **dernière** valeur déjà prise, s'il y en a une : y(avant(t) − 1) ;
- sinon 0.
:::

Pour une sélection, la sortie maintient la valeur entre deux instants de c. Pour une subdivision, elle garde la première valeur de chaque groupe. **[D]**

## La cadence est un signal

Une cadence est une fonction de ℕ dans ℕ : c'est exactement un signal entier de l'horloge parente. Dans un programme, la cadence de c · r est un signal entier, positif ou nul, visible depuis c. Les deux notions dépendent donc l'une de l'autre : un signal a une horloge, et une horloge est une suite de signaux.

**[D] Égalité.** Deux horloges sont égales quand elles sont la même suite de signaux de cadence, comparés par identité d'arbre après mise en forme normale.

## Les trois primitives du langage

| Primitive | Cadence | Nature | Fréquence vue à l'intérieur |
| :--- | :--- | :--- | :--- |
| `ondemand(P)(h)` | h, qui vaut 0 ou 1 | sélection | SR |
| `downsampling(P)(N)` | 1 un instant sur N, 0 sinon | sélection | SR / N |
| `upsampling(P)(N)` | N | subdivision | N · SR |

Ce sont trois vues de la même construction. `downsampling(P)(N)` est un `ondemand` dont la demande est un compteur modulo N écrit sur l'horloge parente. La fréquence d'échantillonnage appartient à la primitive, pas à l'horloge : elle est résolue à la propagation.

# Les opérations

## Trois sortes d'opérations

| Sorte | Exemples | Horloge du résultat |
| :--- | :--- | :--- |
| **sans mémoire** | arithmétique, `select2`, lecture et écriture de table | la plus longue de celles des arguments |
| **à horloge** | `Mem`, `Delay`, `Prefix`, `Fir`, `Iir`, `Irm`, `Waveform`, fonction étrangère sans argument | l'horloge c qu'elle porte |
| **sortie** | `Up` | le parent de l'horloge c qu'elle porte |

Une opération est **à horloge** quand son résultat dépend du nombre d'instants écoulés. Un retard de 1 sur une horloge n'est pas un retard de 1 sur une autre :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes
```

L'écriture de table n'en est pas une : réécrire la même valeur au même index est sans effet, son état ne compte pas le temps. **[D]**

## Règles d'horloge

On note ⊢ s : c pour « s est un signal d'horloge c ».

```inference (nombre)
---
⊢ n : ()
```

```inference (slider)
---
⊢ u : \mathbf{B}
```

```inference (entrée)
---
⊢ x : \mathbf{S}
```

```inference (op)
⊢ s1 : c1; …; ⊢ sn : cn; c1 ≤ c; …; cn ≤ c; c \text{ l'une des } ci
---
⊢ ⋆(s1, …, sn) : c
```

```inference (mem)
⊢ s1 : c1; ⊢ s2 : c2; c1 ≤ c; c2 ≤ c
---
⊢ Delay(c, s1, s2) : c
```

```inference (up)
⊢ y : a; a ≤ p · r
---
⊢ Up(p · r, y) : p
```

```inference (proj)
⊢ def1(W) : c1; …; ⊢ defn(W) : cn; c1 ≤ c; …; cn ≤ c; c \text{ l'une des } ci
---
⊢ Proj(i, W) : c
```

```inference (clk)
⊢ r : a; a ≤ p; r ∈ ℕ
---
p · r \text{ bien formée}
```

- Toutes les règles demandent des arguments visibles depuis l'horloge où ils sont lus. Elles ne peuvent pas échouer dans un programme traduit : dans le contexte lexical c, tout signal a pour horloge un ancêtre de c, et les ancêtres de c forment une chaîne.
- C'est un invariant que chaque transformation doit préserver. Sa vérification est une obligation de certification ; une violation est un défaut du compilateur. **[D]**
- (op) est la règle de temporalité de `ATTRIBUTES.md` : le join des arguments consultés.
- (proj) : les projections d'un groupe partagent une horloge, comme elles partagent une variabilité (« le groupe est couplé »). **[D]**
- (clk) : r entier positif est une obligation de certification, prise sur la forme normale.

## Règles de valeur

Pour les attributs de valeur (nature, booléanité, intervalle), `Up(c, y)` porte y :

- si la cadence vaut au moins 1 au premier instant du parent : la valeur de y. C'est toujours le cas d'une subdivision ;
- sinon : la valeur de y **unie à** 0, ce que vaut la sortie tant que c n'a pas eu d'instant.

La sortie porte l'union avec la valeur initiale, exactement comme le retard dans `FIXPOINT-SPEC.md` (Y@n = Y ⊔ α(0)).

Conséquence à garder en tête : une valeur sortie d'un `ondemand` a 0 dans son intervalle, ce qui pèse sur la certification d'un retard ou d'un index qui en dépend.

L'horloge d'une opération à horloge n'entre dans aucun attribut de valeur.

# La traduction des régions

Pour P : n → m, dans le contexte p, avec c = p · r :

```math
⟦\mathsf{region}(P)⟧_p(r, x_1, …, x_n) = (\mathsf{Up}(c, y_1), …, \mathsf{Up}(c, y_m))
\quad\text{où}\quad (y_1, …, y_m) = ⟦P⟧_c(x_1, …, x_n)
```

Les entrées passent telles quelles : elles sont sur une horloge ancêtre de c, donc visibles depuis c. Il en va de même des sliders, des constantes et des signaux extérieurs capturés. Dans la région, la composition `~` écrit un `Mem(c, …)`. Seules les sorties reçoivent une opération.

La sortie d'une région est toujours un signal de l'horloge parente. Deux régions voisines ne se lisent donc jamais directement. **[D]**

# Lois

On note c = p · r.

Subdivision
:   si r ≥ 1 et si y est un signal d'une horloge ancêtre de p, `Up(c, y)` = y. Entrer puis sortir ne change rien.

Sélection
:   si r ≤ 1, `Up(c, y)` vu de c vaut y. Sortir puis rentrer ne change rien. En particulier `Mem(c, Up(c, y))` = `Mem(c, y)`.

Distribution
:   `Up(c, ⋆(y₁, y₂))` = ⋆(`Up(c, y₁)`, `Up(c, y₂)`), à condition que r(0) ≥ 1 ou que ⋆(0, 0) = 0. Sans cette condition les deux membres diffèrent avant le premier instant de c.

Retards
:   `Delay(c, Delay(c, x, a), b)` = `Delay(c, x, a + b)`, à horloge égale seulement.

Retard vu d'une sélection
:   si r ≤ 1 et si x est un signal d'horloge c, `Mem(p, Up(c, x))` vu de c vaut `Mem(c, x)`.

Composition
:   pour deux cadences booléennes, (p · h₁) · h₀ a les mêmes instants que p · (h₁ × `Up(p · h₁, h₀)`). C'est h₀ ⊗ h₁ de la spec v5.

Cas dégénérés
:   avec r = 1 partout, c a le même temps que p et la remontée est l'identité ; avec r = 0 partout, c n'a aucun instant et toute sortie vaut 0.

La fusion `ondemand(P)(h) : ondemand(Q)(h)` = `ondemand(P:Q)(h)` découle de la loi de sélection et de l'égalité des horloges. Elle est fausse pour un `upsampling`.

# Exemples

On note c = **S** · h. Les codes sont ceux que les règles désignent ; ils n'ont pas été produits par un compilateur.

## Sample and hold

`ondemand(_)` donne `Up(c, x)`.

```c
if (h) { fUp0 = input1[i]; }
output0[i] = fUp0;
```

## Bruit sous-échantillonné

`ba.beat(100) : ondemand(no.noise)`. Le générateur est un groupe V de définition `Mem(c, Proj(0,V)) * 1103515245 + 12345`, d'horloge c. La sortie est `Up(c, Proj(0,V) * 4.65e-10)`. Le code est celui des slides IFC-24.

## Ondemand imbriqués

`ondemand(ondemand(P))` : par la loi de composition, une seule horloge.

## Récursion à travers la frontière

```faust
process(h) = y letrec { 'y = ondemand(+(1))(h, y); };
```

La définition du groupe est `Up(c, Mem(S, Proj(0,U)) + 1)`. Par la loi du retard vu d'une sélection, l'état passe dans la région :

```c
if (h) { iRec0 = iRec0 + 1; }
```

## Upsampling et filtre

`upsampling(+ ~ *(0.5))` avec c = **S** · N. L'entrée, d'horloge **S**, est vue depuis c : elle garde sa valeur pendant les N instants. La sortie est `Up(c, Proj(0,W))`.

```c
for (int j = 0; j < N; j++) {
    fRec0[0] = input1[i] + 0.5f * fRec0[1];
    if (j == 0) { fUp0 = fRec0[0]; }
    fRec0[1] = fRec0[0];
}
output0[i] = fUp0;
```

## Constante

`ondemand(1)` donne `Up(c, 1)` : 0 jusqu'à la première demande, puis 1. C'est la sémantique de la spec v5.

# Parenté avec les langages synchrones

Le calcul décrit une exécution synchrone et causale, et il reprend des notions établies.

- Dans Lustre et Lucid Synchrone, un flot est une suite de valeurs et une horloge est un type, `base` ou `ck on c`. Notre c · r est la même construction, avec une cadence entière au lieu d'un booléen. Voir les [notes de cours de M. Pouzet sur le calcul d'horloges](https://www.di.ens.fr/~pouzet/cours/mpri/cours6/clock-calculus.pdf).
- L'égalité des horloges y est structurelle, comme ici.
- Les domaines réactifs de ReactiveML créent une échelle de temps plus rapide en subdivisant un instant du parent, et leurs instants locaux sont inobservables de l'extérieur. C'est notre subdivision, avec la même sortie par le parent. Voir [Time Refinement in a Functional Synchronous Language](https://www.di.ens.fr/~pouzet/bib/scp15.pdf).

Une différence : dans ces langages tous les opérandes d'une opération ont la même horloge, et l'échantillonnage s'écrit (`when`). Ici un signal d'un repère ancêtre est visible sans opération, et seule la sortie s'écrit.

# La place dans l'approche algébrique

## L'horloge dans la signature

L'arbre de signaux est l'algèbre initiale de la signature (`FAUSTALGEBRA.md`). Si l'arbre portait une horloge que la signature ignore, une transformation qui passe par `Delay(x, d)` rebâtirait un retard sans horloge : c'est la lacune de fidélité décrite dans `LES-ALGEBRES-DE-TRANSFORMATION.md`. L'horloge fait partie de la dénotation d'un retard ; sa place est dans la signature.

**[P]** L'horloge est un opérande, pas une donnée : elle contient des signaux, ses cadences, que chaque interprétation interprète et chaque transformation transforme.

```adt
Clock ::= Root                      (* la racine *)
        | Derive(Clock, rate)       (* une cadence de plus *)

Sig   ::= Up(Clock, y)
        | Mem(Clock, x)
        | Delay(Clock, x, d)
        | Prefix(Clock, x0, x)
        | Fir(Clock, x, coefs)
        | Iir(Clock, x, coefs)
        | Irm(Clock, x, c)
        | Waveform(Clock, w)
```

| Algèbre | Valeur d'une horloge |
| :--- | :--- |
| arbres | le terme d'horloge |
| horloges | l'horloge ; une opération à horloge vaut son horloge |
| intervalles | les bornes de la cadence, pour convertir le temps d'un repère en temps de son parent |
| nature, booléanité | rien |

**[Q] Une ou deux sortes.** Soit l'horloge est un `T` comme les étiquettes, soit la signature a deux paramètres, `FaustAlgebra<T, K>`. Avec deux sortes, confondre un signal et une horloge est une erreur de compilation, et chaque algèbre choisit son `K` ; en contrepartie toutes les algèbres existantes changent de forme. Non tranché.

## Les deux formes

`LA-FORME-DE-CALCUL.md` distingue la forme normale, où l'on certifie, de la forme de calcul, qui porte les décisions comme données.

Forme normale
:   L'horloge est l'opérande ci-dessus. La certification y prouve, pour chaque horloge dérivée, que la cadence est un entier positif et borné.

Forme de calcul
:   La cadence est une décision : l'horloge dérivée porte les bornes certifiées de sa cadence, `Derive(parent, rate, rmin, rmax)`, comme `Delay(L, d, dmin, dmax)`. La génération y lit la forme du code, sans relire d'intervalle : rmax ≤ 1 donne un `if`, rmin ≥ 1 une boucle. L'horloge se porte sur la ligne, `DelayLine(clk, x, n)` ; ses lectures et les prises d'un `Fir` n'en ont pas besoin.

Cône des décisions
:   La cadence d'une horloge atteint une décision mémoire (le nombre d'exécutions d'une région). Elle est dans le cône et n'est jamais réécrite par la forme de calcul.

Typage léger
:   L'horloge y remplace la cadence (constante, bloc, échantillon), dont elle est la généralisation : ce sont les trois premières horloges de la hiérarchie.

## Le point fixe

L'horloge est un attribut exact. Sa graine pour une variable récursive est la racine, et non une valeur pessimiste comme `kSamp` pour la variabilité : un groupe écrit dans un `ondemand` n'est pas sur l'horloge échantillon. Le calcul monte tout seul, parce que toute boucle traverse une opération à horloge.

**[Q]** Garder la racine, ou fournir à l'itérateur l'horloge du contexte.

# Où le code est exécuté

L'horloge d'un signal dit sur quel repère il est défini. Le compilateur choisit en plus où il émet le calcul.

- Une opération à horloge s'exécute sur son horloge, sans choix : un écho inaudible vieillit quand même. La règle `isConditionBoundary` de la branche en devient une conséquence.
- Une opération sans mémoire peut s'exécuter sur son horloge, ou sur toute horloge descendante où elle est lue. Descendre vers une sélection, c'est l'appel par nécessité ; rester sur l'ancêtre d'une subdivision, c'est la sortie des invariants de boucle.

Une région d'horloge est un nœud du graphe de son parent. Chaque horloge a son compteur d'instants. Une sortie coûte une variable qui garde la valeur choisie.

# État de l'implémentation

Rien n'est implémenté au-delà de deux étapes sans effet sur le code généré, sur la branche `ccr-faae028d-7grw0l` de `grame-cncm/faust`, au-dessus de `master-dev-certification-4`.

Étape 0 (`c3a3f794a`)
:   `ClockAlgebra` restreinte aux trois horloges de l'hôte, calculée à côté de la variabilité, et un test de concordance sous `FAUST_CHECK_CLOCKS`. Aucune divergence sur la suite d'impulsions (103 programmes, quatre jeux d'options) ni sur les exemples (259 programmes, environ 206 000 signaux). Code généré identique à la référence sur 2 678 compilations.

Étape 1 (`dc1d83c1d`, `314a6dc05`)
:   Le front-end des trois primitives (mots réservés, boîtes, typage, impression, schéma). La propagation les refuse. Le parser est régénéré par bison 3.8.2 au lieu de 2.3, dans un commit séparé.

La projection de l'horloge sur la variabilité : la racine donne `kKonst`, **B** donne `kBlock`, **S** et toute horloge plus longue donnent `kSamp`.

# Décisions et questions

## Prises

- La sortie d'une région est un signal de l'horloge parente.
- La sortie prend la première valeur de la région pendant l'instant du parent, à défaut la dernière.
- Égalité structurelle des horloges.
- Une entrée d'`upsampling` garde sa valeur pendant tous les instants ; un bourrage de zéros s'écrit dans la région.
- L'écriture de table n'est pas une opération à horloge.
- Les projections d'un groupe partagent une horloge.
- L'horloge est calculée à côté de la variabilité, avec un test de concordance.
- Une branche d'horloge sur chaque opération à horloge, y compris hors région.
- Spécifier d'abord ; implémenter après la bascule de `master-dev`.

## En attente

- La lecture « hiérarchie de repères temporels » de cette version.
- Les trois horloges de l'hôte, avec une racine à un seul instant.
- Une ou deux sortes dans la signature.
- La graine des variables récursives.

## Ouvertes

Q1
:   Une sortie à valeur initiale explicite, qui serait à `Up` ce que `Prefix` est à `Mem`, pour ne pas forcer 0 dans l'intervalle d'une sortie de région.

Q2
:   Les sorties qui collectent plusieurs valeurs (`vectorize`, trames FFT, `interleave`). Le remplissage de table en est une.

Q3
:   `switch(C0..Ck)` : des sélections de cadences complémentaires.

Q4
:   Une cadence tantôt nulle, tantôt supérieure à 1. Le calcul la définit (ni sélection ni subdivision) ; faut-il l'accepter dans le langage ?

Q5
:   La valeur d'une horloge dans le domaine des intervalles, et la conversion de l'horizon entre le temps d'un repère et celui de son parent.

Q6
:   La vectorisation des régions de cadence constante.
