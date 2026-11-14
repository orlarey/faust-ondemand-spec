---
title: Un calcul d'horloges pour Faust
subtitle: Spécification, brouillon v11
date: 14 novembre 2026
document-style: article-a4
language: fr
---

::: toc+
- **Objet et statut** — dire ce que le document spécifie et où en est le travail.
- **Les horloges** — construire le temps sur ℕ et ℚ, sans parler de signaux.
  - **Les dates** — le temps mesuré en échantillons.
  - **Les tops** — une date et une durée.
  - **Les horloges et leurs tops** — des ensembles de tops ; les deux horloges de l'hôte.
  - **Dériver une horloge d'une autre** — découper chaque top en parts égales.
  - **Sélection et subdivision** — les deux cas remarquables de la dérivation.
  - **Le raffinement** — la seule relation entre horloges, et la chaîne qu'elle donne.
  - **Une seule horloge primitive** — les échantillons dérivent des blocs.
- **Les signaux** — poser les valeurs sur les horloges.
  - **Valeurs et signaux** — ce qui est hors du temps, ce qui a une horloge.
  - **Lire un signal à une date quelconque** — la dernière valeur prise.
  - **Quand la lecture est sans perte** — la condition, et la loi de cohérence.
  - **La cadence est un signal** — refermer la boucle entre horloges et signaux.
  - **Les trois primitives du langage** — ondemand, upsampling, downsampling.
  - **Le temps différé** — le remplissage des tables.
- **Les opérations** — dire quelle horloge a le résultat d'une opération.
  - **Trois sortes d'opérations** — sans mémoire, à horloge, changement d'horloge.
  - **Voir un signal d'une autre horloge** — l'opération On.
  - **Règles d'horloge** — les règles d'inférence.
  - **L'invariant de chaîne** — ce que la traduction garantit.
  - **Règles de valeur** — ce que On fait aux intervalles.
- **La traduction des régions** — une traduction uniforme pour les trois primitives.
- **Lois** — les égalités que le compilateur peut appliquer.
- **Exemples** — le calcul déroulé à la main sur six programmes.
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

Le calcul tient en quatre idées : une seule construction d'horloge, une seule relation entre horloges (le raffinement), une seule opération qui change d'horloge (`On`), et une place pour l'horloge dans la signature algébrique.

Les marques **[D]** signalent une décision prise, **[P]** une proposition, **[Q]** une question.

Sources : `spec.md` (ondemand v5), les documents Expressive E, les slides IFC-24, et dans `faust-migration` : `FAUSTALGEBRA.md`, `LES-ALGEBRES-DE-TRANSFORMATION.md`, `ATTRIBUTES.md`, `FIXPOINT-SPEC.md`, `LA-FORME-DE-CALCUL.md`.

# Les horloges

Cette section ne parle que du temps. Les signaux n'arrivent qu'à la section suivante. Tout y est construit sur ℕ et ℚ.

## Les dates

::: definition [Date]
Une **date** est un nombre rationnel positif ou nul, un élément de ℚ⁺.
:::

L'unité est l'échantillon : la date n ∈ ℕ est celle de l'échantillon n, et la date 2,5 est à mi-chemin entre les échantillons 2 et 3.

Les dates sont ordonnées comme les nombres. On n'a pas besoin des réels : toutes les dates du calcul s'obtiennent en divisant des entiers.

## Les tops

::: definition [Top]
Un **top** est un couple (d, δ) formé d'une date d ∈ ℚ⁺ et d'une **durée** δ ∈ ℚ, δ > 0. Il occupe l'intervalle de dates $[d,\ d + δ[$ : il commence à d et dure δ.
:::

Par exemple (3, 1) est l'échantillon 3 : il commence à la date 3 et dure un échantillon.

## Les horloges et leurs tops

::: definition [Horloge]
Une **horloge** est un ensemble de tops dont les intervalles sont deux à deux disjoints.
:::

On peut donc ranger les tops d'une horloge par dates croissantes : premier top, deuxième top, etc.

Deux horloges sont données par l'hôte :

- l'horloge des **échantillons**, $\mathbf{S} = \{(n, 1) \mid n ∈ ℕ\}$ ;
- l'horloge des **blocs**. Si les appels successifs de `compute` commencent aux échantillons b₀ = 0 < b₁ < b₂ < …, alors $\mathbf{B} = \{(b_k,\ b_{k+1} - b_k) \mid k ∈ ℕ\}$ : un top par bloc, qui commence avec le bloc et dure autant que lui.

Avec des blocs de 64 échantillons, $\mathbf{B} = \{(0, 64), (64, 64), (128, 64), …\}$.

## Dériver une horloge d'une autre

On fabrique une horloge à partir d'une autre en découpant chacun de ses tops en parts égales.

::: definition [Horloge dérivée]
Soit p une horloge, et r : p → ℕ une fonction qui donne à chaque top de p un entier. L'horloge **dérivée** p ▷ r remplace chaque top τ = (d, δ) de p par r(τ) tops de durée δ / r(τ), mis bout à bout à partir de d :

```math
p ▷ r = \left\{ \left(d + j \cdot \frac{δ}{r(τ)},\ \frac{δ}{r(τ)}\right) \;\middle|\; τ = (d, δ) ∈ p,\ 0 ≤ j < r(τ) \right\}
```

On appelle p le **parent** et r la **cadence**.
:::

| r(τ) | Ce que devient le top τ = (d, δ) |
| :--- | :--- |
| 0 | rien : le top est supprimé |
| 1 | lui-même |
| n > 1 | n tops de durée δ / n, aux dates d, d + δ/n, … |

Le premier des tops issus de τ commence toujours à la date de τ. **[D]**

Un exemple, sur quatre échantillons :

```
p        :  (0,1)        (1,1)        (2,1)                    (3,1)
r        :   1            0            3                         1
p ▷ r    :  (0,1)                     (2,⅓) (2⅓,⅓) (2⅔,⅓)      (3,1)
```

L'échantillon 1 est supprimé. L'échantillon 2 est découpé en trois tops, qui restent tous à l'intérieur de l'intervalle $[2, 3[$.

## Sélection et subdivision

Deux cas de la dérivation sont remarquables.

Sélection
:   r ne vaut jamais plus de 1. La dérivation ne fait que **supprimer** des tops, et p ▷ r ⊆ p : c'est un sous-ensemble de p.

Subdivision
:   r vaut toujours au moins 1. La dérivation ne fait que **découper** des tops.

Dans l'exemple ci-dessus, r fait les deux.

## Le raffinement

::: definition [Raffinement]
c **raffine** p, noté p ≤ c, quand c s'obtient à partir de p par une subdivision, ou par plusieurs subdivisions successives.
:::

Si c raffine p, alors :

- chaque top de p est exactement recouvert par des tops de c ;
- toute date où commence un top de p est une date où commence un top de c ;
- p et c commencent à la même date.

Une sélection ne raffine pas son parent, et son parent ne la raffine pas.

Une horloge dérivée a un seul parent. Les horloges qu'une horloge c raffine se rangent donc en file, de la moins fine à la plus fine. On note Ch(c) cette **chaîne**, c comprise.

## Une seule horloge primitive

L'horloge des échantillons se dérive de celle des blocs. Prenons pour cadence la longueur du bloc, $\mathit{count}(b_k,\ b_{k+1} - b_k) = b_{k+1} - b_k$ : chaque bloc est découpé en tops de durée 1. Donc

```math
\mathbf{S} = \mathbf{B} ▷ \mathit{count}
```

C'est une subdivision : **S** raffine **B**. Toutes les horloges du calcul s'obtiennent ainsi à partir de la seule horloge **B**, par dérivation :

```adt
K ::= B              (* l'horloge des blocs *)
    | Derive(K, r)   (* K ▷ r, r une cadence *)
```

Deux exemples de chaînes :

- pour c = **S** ▷ 4 (chaque échantillon découpé en quatre) : Ch(c) = {**B**, **S**, c} ;
- pour c = **S** ▷ h avec h ≤ 1 (une sélection) : Ch(c) = {c}.

# Les signaux

## Valeurs et signaux

::: definition [Valeur, signal]
Une **valeur** est un nombre, un élément de ℝ. Elle est hors du temps.

Un **signal** d'horloge H est une fonction x : H → ℝ. Il a une valeur x(τ) à chaque top τ de son horloge, et il n'est défini nulle part ailleurs.
:::

Les entrées audio sont des signaux d'horloge **S**, les sliders des signaux d'horloge **B**.

## Lire un signal à une date quelconque

On a souvent besoin de la valeur d'un signal à une date où aucun de ses tops ne commence. On prend alors sa valeur au dernier top commencé.

::: definition [Lecture]
La valeur d'un signal x d'horloge H, **lue** à la date t ∈ ℚ⁺ :

```math
x⌊t⌋ = \begin{cases}
x(d, δ) & \text{où } (d, δ) \text{ est le top de } H \text{ de plus grande date } d ≤ t \\
0 & \text{si aucun top de } H \text{ n'a commencé à la date } t
\end{cases}
```
:::

Seule la date des tops compte pour la lecture, pas leur durée : la valeur est maintenue jusqu'au top suivant, même s'il est lointain.

## Quand la lecture est sans perte

Soit x un signal d'horloge H, lu à chaque top d'une horloge H′.

- Si toute date où commence un top de H est une date où commence un top de H′, la lecture ne perd rien : chaque valeur de x est vue, et maintenue jusqu'à la suivante. C'est le cas quand H′ raffine H (un slider lu à chaque échantillon), et aussi quand H est une sélection de H′.
- Sinon elle peut en perdre : une valeur de x remplacée avant le top suivant de H′ n'est jamais vue.

::: proposition [Cohérence]
Dans le premier cas, lire x directement à une date, ou lire d'abord x sur H′ puis relire le résultat à cette date, donne la même chose.
:::

## La cadence est un signal

Dans la définition de l'horloge dérivée, la cadence était une fonction quelconque de p dans ℕ. C'est exactement ce qu'est un signal entier d'horloge p. Dans un programme, la cadence de p ▷ r est un tel signal. Les deux notions dépendent donc l'une de l'autre : un signal a une horloge, et une horloge dérivée est construite avec un signal.

**[D] Égalité.** Deux horloges dérivées sont égales quand elles ont le même parent et le même signal de cadence, comparé par identité d'arbre après mise en forme normale.

## Les trois primitives du langage

| Primitive | Cadence | Nature | Fréquence vue à l'intérieur |
| :--- | :--- | :--- | :--- |
| `ondemand(P)(h)` | h, qui vaut 0 ou 1 | sélection | SR |
| `downsampling(P)(N)` | 1 un top sur N, 0 sinon | sélection | SR / N |
| `upsampling(P)(N)` | N | subdivision | N · SR |

Ce sont trois vues de la même construction. `downsampling(P)(N)` est un `ondemand` dont la demande est un compteur modulo N écrit sur l'horloge parente. La fréquence d'échantillonnage appartient à la primitive, pas à l'horloge : elle est résolue à la propagation.

## Le temps différé

Le remplissage d'une table de taille n est le calcul d'un signal sur une horloge finie de n tops, placés avant la date 0 : c'est la seule horloge dont les dates sont négatives, et une seconde horloge primitive. La table collecte les n valeurs ; pour le temps réel c'est une valeur.

Le temps-programme (compilation, initialisation, exécution) n'est pas une horloge de signal : c'est la calculabilité, l'autre axe de `ATTRIBUTES.md`.

# Les opérations

## Trois sortes d'opérations

| Sorte | Exemples | Horloge du résultat |
| :--- | :--- | :--- |
| **sans mémoire** | arithmétique, `select2`, lecture et écriture de table | la plus fine de celles des arguments |
| **à horloge** | `Mem`, `Delay`, `Prefix`, `Fir`, `Iir`, `Irm`, `Waveform`, fonction étrangère sans argument | l'horloge k qu'elle porte |
| **changement d'horloge** | `On` | l'horloge k qu'elle porte |

Une opération est **à horloge** quand son résultat dépend du nombre de tops écoulés. Un retard de 1 sur une horloge n'est pas un retard de 1 sur une autre :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes
```

L'écriture de table n'en est pas une : réécrire la même valeur au même index est sans effet, son état ne compte pas le temps. **[D]**

## Voir un signal d'une autre horloge

::: definition [On]
`On(k, x)` est le signal d'horloge k dont la valeur, à chaque top de k, est x lu à la date de ce top :

```math
\mathsf{On}(k, x)(d, δ) = x⌊d⌋
```

Appliqué à une valeur v, c'est le signal d'horloge k qui vaut v à chaque top.
:::

Selon les horloges, `On` échantillonne (quand k est une sélection de l'horloge de x), maintient (quand k la raffine), ou les deux.

## Règles d'horloge

On note ⊢ s : k pour « s est un signal d'horloge k » et ⊢ s : ⊥ pour « s est une valeur ». On pose ⊥ ≤ k pour tout k.

```inference (nombre)
---
⊢ n : ⊥
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
⊢ s1 : k1; …; ⊢ sn : kn; k1, …, kn \text{ en chaîne}
---
⊢ ⋆(s1, …, sn) : max(k1, …, kn)
```

```inference (mem)
⊢ s1 : k1; ⊢ s2 : k2; k1 ≤ k; k2 ≤ k
---
⊢ Delay(k, s1, s2) : k
```

```inference (on)
---
⊢ On(k, s) : k
```

```inference (proj)
⊢ def1(W) : k1; …; ⊢ defn(W) : kn; k1, …, kn \text{ en chaîne}
---
⊢ Proj(i, W) : max(k1, …, kn)
```

```inference (clk)
⊢ r : k; k ≤ p; r ∈ ℕ
---
p ▷ r \text{ bien formée}
```

- (op) et (mem) demandent des arguments dont l'horloge est raffinée par celle du résultat : ils sont lus sans perte. Seul `On` accepte un argument quelconque.
- C'est la règle de temporalité de `ATTRIBUTES.md` : la borne intrinsèque de l'opération, unie au join des arguments consultés.
- (proj) : les projections d'un groupe partagent une horloge, comme elles partagent une variabilité (« le groupe est couplé »). **[D]**
- (clk) : r entier positif est une obligation de certification, prise sur la forme normale.

## L'invariant de chaîne

**[D]** Dans le contexte lexical c, tout signal a une horloge de Ch(c).

Les prémisses de (op), (mem) et (proj) sont donc toujours satisfaites. Ce n'est pas une contrainte pour l'utilisateur : la traduction des régions établit l'invariant, chaque transformation doit le préserver, et sa vérification est une obligation de certification. Une violation est un défaut du compilateur.

## Règles de valeur

Pour les attributs de valeur (nature, booléanité, intervalle), `On(k, x)` porte x :

- quand aucun top de k ne peut précéder le premier top de x : la valeur de x. C'est le cas si k est une sélection de l'horloge de x, si elle la raffine, ou si elle est raffinée par elle ;
- sinon : la valeur de x **unie à** 0, ce que rend la lecture tant que x n'a pas commencé.

Le maintien porte l'union avec la valeur initiale, exactement comme le retard dans `FIXPOINT-SPEC.md` (Y@n = Y ⊔ α(0)). Le raffinement, lui, n'ajoute jamais de 0 : une horloge et celles qui la raffinent commencent à la même date.

Conséquence à garder en tête : une valeur sortie d'un `ondemand` a 0 dans son intervalle, ce qui pèse sur la certification d'un retard ou d'un index qui en dépend.

L'horloge d'une opération à horloge n'entre dans aucun attribut de valeur.

# La traduction des régions

Pour P : n → m, dans le contexte p, avec c = p ▷ r :

```math
⟦\mathsf{region}(P)⟧_p(r, x_1, …, x_n) = (\mathsf{On}(p, \mathsf{On}(c, y_1)), …, \mathsf{On}(p, \mathsf{On}(c, y_m)))
```

```math
\text{où}\quad (y_1, …, y_m) = ⟦P⟧_c(\mathsf{On}(c, x_1), …, \mathsf{On}(c, x_n))
```

Toute feuille écrite dans P (slider, entrée, signal extérieur capturé) est traduite `On(c, feuille)`. La composition `~` écrit un `Mem(c, …)`. Les nombres restent des valeurs.

Une seule loi décide de ce qui reste : `On(k, x)` = x quand x est un signal dont l'horloge est raffinée par k.

| | `ondemand`, `downsampling` | `upsampling` |
| :--- | :--- | :--- |
| entrée `On(c, x)` | reste : échantillonnage | s'efface : p ≤ c, maintien sur les tops issus du même top parent |
| sortie `On(c, y)` | s'efface si y est un signal | s'efface si y est un signal |
| sortie `On(p, …)` | reste : maintien entre deux demandes | reste : premier sous-échantillon |

La sortie est toujours un signal de l'horloge parente : c'est ce qui établit l'invariant de chaîne, sans règle particulière. Deux régions voisines ne se lisent jamais directement.

# Lois

Effacement
:   `On(k, x)` = x si x est un signal d'horloge k′ ≤ k.

Absorption
:   `On(k, On(k′, x))` = `On(k, x)` si k est une sélection de k′, ou si k′ raffine k.

Distribution
:   `On(k, ⋆(x₁, x₂))` = ⋆(`On(k, x₁)`, `On(k, x₂)`).

Retards
:   `Delay(k, Delay(k, x, a), b)` = `Delay(k, x, a + b)`, à horloge égale seulement.

Retard vu d'une sélection
:   pour c sélection de p et x d'horloge c, `On(c, Mem(p, On(p, x)))` = `Mem(c, x)`.

Composition
:   (p ▷ h₁) ▷ h₀ = p ▷ (h₁ · h₀) pour des cadences booléennes. C'est h₀ ⊗ h₁ de la spec v5.

Cas dégénérés
:   p ▷ 1 = p ; p ▷ 0 est l'horloge vide, dont tous les signaux se lisent 0.

La fusion `ondemand(P)(h) : ondemand(Q)(h)` = `ondemand(P:Q)(h)` découle de l'absorption et de l'égalité structurelle. Elle est fausse pour un `upsampling`.

**[P] Forme canonique** : la distribution fait remonter `On` vers les consommateurs.

# Exemples

On note c = **S** ▷ h. Les codes sont ceux que les règles désignent ; ils n'ont pas été produits par un compilateur.

## Sample and hold

`ondemand(_)` donne `On(S, On(c, x))`.

```c
if (h) { fOn0 = input1[i]; }
output0[i] = fOn0;
```

## Bruit sous-échantillonné

`ba.beat(100) : ondemand(no.noise)`. Le générateur est un groupe V de définition `Mem(c, Proj(0,V)) * 1103515245 + 12345`, d'horloge c. La sortie est `On(S, Proj(0,V) * 4.65e-10)`. Le code est celui des slides IFC-24.

## Ondemand imbriqués

`ondemand(ondemand(P))` : par la loi de composition, une seule horloge de cadence h₁ · h₀.

## Récursion à travers la frontière

```faust
process(h) = y letrec { 'y = ondemand(+(1))(h, y); };
```

Par la loi du retard vu d'une sélection, l'état passe dans la région :

```c
if (h) { iRec0 = iRec0 + 1; }
```

## Upsampling et filtre

`upsampling(+ ~ *(0.5))` : c = **S** ▷ N raffine **S**, l'entrée s'efface, la sortie est `On(S, Proj(0,W))`.

```c
for (int j = 0; j < N; j++) {
    fRec0[0] = input1[i] + 0.5f * fRec0[1];
    if (j == 0) { fOn0 = fRec0[0]; }
    fRec0[1] = fRec0[0];
}
output0[i] = fOn0;
```

## Constante

`ondemand(1)` donne `On(S, On(c, 1))` : 0 jusqu'à la première demande, puis 1. C'est la sémantique de la spec v5.

# La place dans l'approche algébrique

## L'horloge dans la signature

L'arbre de signaux est l'algèbre initiale de la signature (`FAUSTALGEBRA.md`). Si l'arbre portait une horloge que la signature ignore, une transformation qui passe par `Delay(x, d)` rebâtirait un retard sans horloge : c'est la lacune de fidélité décrite dans `LES-ALGEBRES-DE-TRANSFORMATION.md`. L'horloge fait partie de la dénotation d'un retard ; sa place est dans la signature.

**[P]** L'horloge est un opérande, pas une donnée : elle contient un signal, la cadence, que chaque interprétation interprète et chaque transformation transforme.

```adt
Clock ::= ClockBlock                (* l'horloge des blocs *)
        | Derive(Clock, rate)       (* l'horloge dérivée *)

Sig   ::= On(Clock, x)
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
| intervalles | les bornes de la cadence, pour convertir le temps local en temps parent |
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
:   L'horloge y remplace la cadence (constante, bloc, échantillon), dont elle est la généralisation.

## Le point fixe

L'horloge est un attribut exact. Sa graine pour une variable récursive est le bas (⊥), et non une valeur pessimiste comme `kSamp` pour la variabilité : un groupe écrit dans un `ondemand` n'est pas sur l'horloge échantillon. Le calcul monte tout seul, parce que toute boucle traverse une opération à horloge.

**[Q]** Garder le bas, ou fournir à l'itérateur l'horloge du contexte.

# Où le code est exécuté

L'horloge d'un signal dit quand sa valeur peut changer. Le compilateur choisit en plus où il émet le calcul.

- Une opération à horloge s'exécute sur son horloge, sans choix : un écho inaudible vieillit quand même. La règle `isConditionBoundary` de la branche en devient une conséquence.
- Une opération sans mémoire peut s'exécuter sur toute horloge qui contient les dates où elle est lue (loi de cohérence). Vers une horloge plus rare, c'est l'appel par nécessité ; vers une horloge moins fine, la sortie des invariants de boucle.

Une région d'horloge est un nœud du graphe de son parent. Chaque horloge a son index de temps. Lire un signal hors de son horloge coûte une variable qui garde sa dernière valeur.

# État de l'implémentation

Rien n'est implémenté au-delà de deux étapes sans effet sur le code généré, sur la branche `ccr-faae028d-7grw0l` de `grame-cncm/faust`, au-dessus de `master-dev-certification-4`.

Étape 0 (`c3a3f794a`)
:   `ClockAlgebra` restreinte aux horloges naturelles, calculée à côté de la variabilité, et un test de concordance sous `FAUST_CHECK_CLOCKS`. Aucune divergence sur la suite d'impulsions (103 programmes, quatre jeux d'options) ni sur les exemples (259 programmes, environ 206 000 signaux). Code généré identique à la référence sur 2 678 compilations.

Étape 1 (`dc1d83c1d`, `314a6dc05`)
:   Le front-end des trois primitives (mots réservés, boîtes, typage, impression, schéma). La propagation les refuse. Le parser est régénéré par bison 3.8.2 au lieu de 2.3, dans un commit séparé.

La projection de l'horloge sur la variabilité : une valeur donne `kKonst`, **B** donne `kBlock`, **S** et toute horloge dérivée donnent `kSamp`.

# Décisions et questions

## Prises

- Un top découpé commence à la date de son parent, et ses parts restent dans sa durée.
- Égalité structurelle des horloges.
- La sortie d'une région est un signal de l'horloge parente.
- Maintien en entrée d'`upsampling` ; un bourrage de zéros s'écrit dans la région.
- L'écriture de table n'est pas une opération à horloge.
- Les projections d'un groupe partagent une horloge.
- L'horloge est calculée à côté de la variabilité, avec un test de concordance.
- Une branche d'horloge sur chaque opération à horloge, y compris hors région.
- Spécifier d'abord ; implémenter après la bascule de `master-dev`.

## En attente

- Une ou deux sortes dans la signature.
- La graine des variables récursives.

## Ouvertes

Q1
:   Un maintien à valeur initiale explicite, qui serait à `On` ce que `Prefix` est à `Mem`, pour ne pas forcer 0 dans l'intervalle d'une sortie de région.

Q2
:   Les sorties qui collectent plusieurs valeurs (`vectorize`, trames FFT, `interleave`). Le remplissage de table en est une.

Q3
:   `switch(C0..Ck)` : des sélections de cadences complémentaires.

Q4
:   Une cadence tantôt nulle, tantôt supérieure à 1. Le calcul la définit (ni sélection ni subdivision) ; faut-il l'accepter dans le langage ?

Q5
:   La valeur d'une horloge dans le domaine des intervalles, et la conversion de l'horizon entre temps local et temps parent.

Q6
:   La vectorisation des régions de cadence constante.
