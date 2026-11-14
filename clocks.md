---
title: Un calcul d'horloges pour Faust
subtitle: Spécification, brouillon v13
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
  - **Le repère du haut** — les étapes du programme : les tables, puis les blocs.
- **Les signaux** — poser les valeurs sur les repères.
  - **Un signal et son horloge** — une valeur par instant.
  - **Voir un signal depuis un repère descendant** — composer avec la remontée.
  - **Sortir un signal vers le repère parent** — la dernière valeur calculée.
  - **La cadence est un signal** — refermer la boucle entre horloges et signaux.
- **La sémantique** — le crochet indicé par un repère, et ses règles.
- **Les régions** — les trois primitives et leur traduction.
  - **Les trois primitives du langage** — ondemand, upsampling, downsampling.
  - **La traduction** — une traduction uniforme.
  - **Un retard dans chaque région** — le même exemple déroulé trois fois.
- **Les tables** — l'initialisation comme suite d'instants du repère du haut.
- **Les règles d'horloge** — dire quelle horloge a le résultat d'une opération.
  - **Trois sortes d'opérations** — sans mémoire, à horloge, sortie.
  - **Les règles** — les règles d'inférence.
  - **Règles de valeur** — ce que la sortie fait aux intervalles.
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

L'idée directrice : il n'y a pas de temps global. Chaque horloge est un **repère temporel** dont le temps est simplement ℕ, et les repères forment une hiérarchie. On passe d'un repère à son parent par une fonction, la remontée. La sémantique de Faust garde sa forme ; son crochet reçoit seulement un indice, le repère d'où l'on regarde.

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

Le nombre d'instants de la nouvelle horloge qui ont eu lieu à la fin de l'instant t du parent est

```math
\mathit{fait}(t) = r(0) + r(1) + … + r(t)
```

::: definition [Remontée]
La **remontée** π : ℕ → ℕ associe à chaque instant n de la nouvelle horloge l'instant du parent pendant lequel il a lieu : π(n) est le plus petit t tel que fait(t) > n.
:::

La remontée est croissante. La cadence et la remontée disent la même chose : r(t) est le nombre d'instants n tels que π(n) = t.

Un exemple, avec la cadence 1, 0, 3, 1 :

```
instant du parent   t   :   0     1     2           3
cadence           r(t)  :   1     0     3           1
fait(t)                 :   1     1     4           5
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

Une horloge dérivée a un parent, qui peut lui-même en avoir un. En remontant on finit par atteindre l'horloge sans parent, le **repère du haut**, noté ⊤.

::: definition [Horloge]
Une **horloge** est la suite des cadences qui y mènent depuis le repère du haut : c = (r₁, r₂, …, rₖ). Le repère du haut est la suite vide. Le **parent** de (r₁, …, rₖ) est (r₁, …, rₖ₋₁), et rₖ est une cadence sur le temps de ce parent.
:::

On note c · r l'horloge obtenue en ajoutant la cadence r à c.

Les **ancêtres** d'une horloge sont ses préfixes, elle-même comprise. On note a ≤ c quand a est un ancêtre de c. Les ancêtres d'une horloge sont rangés par longueur : ils forment une chaîne, du repère du haut jusqu'à elle.

Pour remonter d'une horloge c à l'un de ses ancêtres a, on compose les remontées successives. On note π(c → a) cette remontée composée ; π(c → c) est l'identité.

Deux horloges quelconques ont toujours un plus proche ancêtre commun, leur plus long préfixe commun. Si aucune n'est l'ancêtre de l'autre, elles sont **incompatibles** : leurs signaux ne se rencontrent qu'après être sortis jusqu'à cet ancêtre commun. Avec un élément « incompatible » ajouté en bas, les horloges forment un treillis dont le repère du haut est le sommet.

## Le repère du haut

Le temps du repère du haut est la suite des **étapes** du programme : d'abord une étape par table à remplir, puis une étape par bloc. **[D]**

Avec trois tables :

```
⊤     t :   0          1          2          3        4        5   …
            table 1    table 2    table 3    bloc 0   bloc 1   bloc 2
```

C'est une succession d'instants ordinaire, infinie. Sous le repère du haut se trouvent les **repères de base**, chacun étant la subdivision d'une ou plusieurs étapes :

| Repère de base | Cadence depuis le repère du haut | Son temps |
| :--- | :--- | :--- |
| table i, de taille nᵢ | nᵢ à l'étape i, 0 ailleurs | nᵢ instants |
| échantillons **S** | 0 pendant les étapes des tables, puis la longueur de chaque bloc | infini |

Le premier échantillon n'a donc pas lieu pendant une étape d'initialisation : il a lieu pendant l'étape du premier bloc.

Sous chaque repère de base, on construit des régions par les mêmes dérivations. Le calcul ne distingue pas l'initialisation de l'exécution : seule change l'étape qui héberge le repère de base.

**[D]** Aucune opération qui compte le temps n'est écrite sur le repère du haut. `process` est traduit dans le repère des échantillons, chaque générateur dans le repère de sa table. Le repère du haut ne porte que des signaux sans mémoire : les constantes, les tables une fois remplies, et **[P]** les sliders.

# Les signaux

## Un signal et son horloge

::: definition [Signal]
Un **signal** d'horloge c est une fonction qui donne une valeur réelle à chaque instant de c.
:::

- Une constante est un signal du repère du haut, qui prend la même valeur à chaque étape.
- Une entrée audio est un signal d'horloge **S** : une valeur par échantillon.

## Voir un signal depuis un repère descendant

Un signal est visible dans tous les repères qui descendent du sien : il suffit de remonter.

::: definition [Vue]
Soit x un signal d'horloge a, et c une horloge dont a est un ancêtre. La **vue** de x depuis c est le signal d'horloge c qui vaut, à l'instant n, la valeur de x à l'instant π(c → a)(n).
:::

C'est une simple composition. Elle ne demande aucune opération dans le programme :

- une constante, vue de n'importe où, vaut toujours la même chose ;
- une entrée audio vue d'un `ondemand` y prend la valeur qu'elle a aux échantillons où la demande est faite ;
- une entrée audio vue d'un `upsampling` par N y garde sa valeur pendant N instants.

Depuis une subdivision, on voit toutes les valeurs du signal, chacune répétée. Depuis une sélection, on ne voit que certaines d'entre elles.

## Sortir un signal vers le repère parent

Dans l'autre sens, il n'y a pas de fonction : pendant un instant du parent, une horloge peut avoir plusieurs instants, ou aucun. Sortir un signal demande donc de choisir une valeur. C'est la seule opération du calcul.

::: definition [Sortie]
Soit c = p · r, et y un signal visible depuis c. La **sortie** `Up(c, y)` est le signal d'horloge p qui vaut, à l'instant t de p, la valeur de y au **dernier instant de c déjà fait** à la fin de t, c'est-à-dire à l'instant fait(t) − 1 de c. S'il n'y en a encore aucun, elle vaut 0.
:::

Pour une sélection, la sortie maintient la valeur entre deux instants de c. Pour une subdivision, elle rend la dernière valeur de chaque groupe : le résultat des itérations faites pendant l'instant du parent. **[D]**

C'est la fonction h⁺ de la spec v5, étendue sans changement aux cadences supérieures à 1.

## La cadence est un signal

Une cadence est une fonction de ℕ dans ℕ : c'est exactement un signal entier de l'horloge parente. Dans un programme, la cadence de c · r est un signal entier, positif ou nul, visible depuis c. Les deux notions dépendent donc l'une de l'autre : un signal a une horloge, et une horloge est une suite de signaux.

**[D] Égalité.** Deux horloges sont égales quand elles sont la même suite de signaux de cadence, comparés par identité d'arbre après mise en forme normale.

# La sémantique

La sémantique de Faust donne à chaque signal une fonction du temps. Ici le crochet reçoit un indice : ⟦s⟧ indicé par c est le signal s **vu du repère c**, et son argument est un instant de c. La sémantique habituelle est le cas où c est le repère des échantillons.

Avant l'instant 0
:   Tout signal, vu de n'importe quel repère, vaut 0 avant l'instant 0 de ce repère.

```math
⟦s⟧_c(n) = 0 \qquad \text{pour } n < 0
```

Constante
:   Elle vaut la même chose à tout instant positif de tout repère.

```math
⟦k⟧_c(n) = k \qquad \text{pour } n ≥ 0
```

Opération sans mémoire
:   Elle s'applique instant par instant.

```math
⟦⋆(x, y)⟧_c(n) = ⋆(⟦x⟧_c(n),\ ⟦y⟧_c(n)) \qquad \text{pour } n ≥ 0
```

Retard
:   C'est la formule habituelle, dans le repère c que porte le retard.

```math
⟦\mathsf{Delay}(c, x, d)⟧_c(n) = ⟦x⟧_c(n - ⟦d⟧_c(n)) \qquad \text{pour } n ≥ 0
```

Vue
:   Un signal d'horloge a, regardé depuis un repère descendant c, se lit en remontant.

```math
⟦s⟧_c(n) = ⟦s⟧_a(π(c → a)(n))
```

Sortie
:   Avec c = p · r, la cadence étant elle-même lue dans p pour calculer fait(t).

```math
⟦\mathsf{Up}(c, y)⟧_p(t) = ⟦y⟧_c(\mathit{fait}(t) - 1)
```

Seules les deux dernières règles sont nouvelles. Ce sont les deux seuls endroits où l'indice du crochet change.

Pour que la première règle soit cohérente avec la vue, on prolonge la remontée : un instant négatif d'un repère remonte sur un instant négatif de son parent. La sortie vaut alors bien 0 tant que fait(t) = 0.

**Voir puis retarder n'est pas retarder puis voir.** Un retard d'horloge c, regardé depuis un repère plus profond, reste calculé dans c : c'est la règle de vue qui s'applique, pas celle du retard. L'horloge portée par le retard fixe le repère où l'on compte.

# Les régions

## Les trois primitives du langage

| Primitive | Cadence | Nature | Fréquence vue à l'intérieur |
| :--- | :--- | :--- | :--- |
| `ondemand(P)(h)` | h, qui vaut 0 ou 1 | sélection | SR |
| `downsampling(P)(N)` | 1 un instant sur N, 0 sinon | sélection | SR / N |
| `upsampling(P)(N)` | N | subdivision | N · SR |

Ce sont trois vues de la même construction. `downsampling(P)(N)` est un `ondemand` dont la demande est un compteur modulo N écrit sur l'horloge parente. La fréquence d'échantillonnage appartient à la primitive, pas à l'horloge : elle est résolue à la propagation.

## La traduction

Pour P : n → m, dans le contexte p, avec c = p · r :

```math
⟦\mathsf{region}(P)⟧_p(r, x_1, …, x_n) = (\mathsf{Up}(c, y_1), …, \mathsf{Up}(c, y_m))
\quad\text{où}\quad (y_1, …, y_m) = ⟦P⟧_c(x_1, …, x_n)
```

Les entrées passent telles quelles : elles sont sur une horloge ancêtre de c, donc visibles depuis c. Il en va de même des constantes et des signaux extérieurs capturés. Dans la région, la composition `~` écrit un `Mem(c, …)`. Seules les sorties reçoivent une opération.

La sortie d'une région est toujours un signal de l'horloge parente. Deux régions voisines ne se lisent donc jamais directement. **[D]**

## Un retard dans chaque région

Le même programme, `1@2`, plongé dans les trois régions. Hors de toute région, `Delay(S, 1, 2)` vaut 0, 0, puis 1. Dans une région d'horloge c, on note y = `Delay(c, 1, 2)` ; la sortie est `Up(c, y)`.

Dans un `ondemand` :

```
échantillon      t :  0  1  2  3  4  5  6  7  8  9
demande          h :  0  0  1  0  0  1  1  0  1  0
fait(t)            :  0  0  1  1  1  2  3  3  4  4
instants de c    n :        0        1  2     3
y vu de c          :        0        0  1     1
Up(c, y)           :  0  0  0  0  0  0  1  1  1  1
```

Dans un `upsampling` par 3 :

```
échantillon      t :  0        1        2
instants de c    n :  0  1  2  3  4  5  6  7  8
y vu de c          :  0  0  1  1  1  1  1  1  1
fait(t)            :  3        6        9
Up(c, y)           :  1        1        1
```

Dans un `downsampling` par 3 :

```
échantillon      t :  0  1  2  3  4  5  6  7  8  9
cadence          r :  1  0  0  1  0  0  1  0  0  1
fait(t)            :  1  1  1  2  2  2  3  3  3  4
instants de c    n :  0        1        2        3
y vu de c          :  0        0        1        1
Up(c, y)           :  0  0  0  0  0  0  1  1  1  1
```

Pour un retard d écrit dans la région, la sortie passe à 1 :

| Contexte | La sortie passe à 1 | Avec d = 2 |
| :--- | :--- | :--- |
| aucune région | à l'échantillon d | échantillon 2 |
| `ondemand` | à la demande numéro d + 1 | troisième demande |
| `upsampling` par N | à l'échantillon ⌊d / N⌋ | échantillon 0 |
| `downsampling` par N | à l'échantillon d × N | échantillon 6 |

Dans un `upsampling`, un retard plus court que le facteur est invisible de l'extérieur : il est absorbé par les itérations faites pendant l'échantillon.

# Les tables

Le remplissage d'une table de taille n est le calcul d'un signal sur un repère de base qui a n instants, tous pendant une même étape du repère du haut. Le générateur est un circuit sans entrée, traduit dans ce repère : ses retards et ses récursions y avancent d'un pas par instant. « Les n premiers instants d'un signal » se lit littéralement.

Le générateur d'une table est un programme comme un autre. Il peut contenir des régions :

```faust
gen = ondemand(P)(h) : upsampling(Q)(4);
process = rdtable(1024, gen, index);
```

```
⊤   étapes : la table, puis les blocs
├─ T              1024 instants pendant l'étape 0
│  ├─ T · h       l'ondemand du générateur
│  └─ T · 4       l'upsampling du générateur
└─ S              les échantillons
   └─ régions de process
```

**La sortie d'une table.** Une sortie `Up` ne garderait que la dernière des n valeurs. La table les garde toutes : `Collect(T, g)` est le signal du repère du haut qui vaut, à partir de l'étape de la table, le tableau des n valeurs de g. Lire la table est ensuite une opération sans mémoire : indexer ce tableau. **[P]**

**Les dépendances entre tables.** Le générateur d'une table peut lire une autre table. Les tables forment un graphe de dépendances, que l'on sérialise : chaque table reçoit une étape, postérieure à celles des tables qu'elle lit. Une table ne lit donc que le passé, et l'exécution vient après toutes. **[D]**

Deux conditions accompagnent ce choix :

- le sens du programme ne dépend pas de l'ordre choisi entre deux tables indépendantes, puisqu'elles ne se lisent pas ;
- l'ordre doit être fixé par une règle, pour que le compilateur reste déterministe : le numéro d'étape d'une table entre dans son horloge.

**Les cas croisés.** Une table est un signal du repère du haut : elle est visible de partout, y compris d'une région de l'exécution ou du générateur d'une table postérieure. La même expression écrite dans un générateur et dans `process` porte deux horloges différentes, et ses états ne sont pas partagés.

# Les règles d'horloge

## Trois sortes d'opérations

| Sorte | Exemples | Horloge du résultat |
| :--- | :--- | :--- |
| **sans mémoire** | arithmétique, `select2`, lecture et écriture de table | la plus longue de celles des arguments |
| **à horloge** | `Mem`, `Delay`, `Prefix`, `Fir`, `Iir`, `Irm`, `Waveform`, fonction étrangère sans argument | l'horloge c qu'elle porte |
| **sortie** | `Up`, `Collect` | le parent de l'horloge c qu'elle porte |

Une opération est **à horloge** quand son résultat dépend du nombre d'instants écoulés. Un retard de 1 sur une horloge n'est pas un retard de 1 sur une autre :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes
```

L'écriture de table n'en est pas une : réécrire la même valeur au même index est sans effet, son état ne compte pas le temps. **[D]**

## Les règles

On note ⊢ s : c pour « s est un signal d'horloge c ».

```inference (constante)
---
⊢ k : ⊤
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
⊢ s1 : c1; ⊢ s2 : c2; c1 ≤ c; c2 ≤ c; c ≠ ⊤
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

`upsampling(+ ~ *(0.5))` avec c = **S** · N. L'entrée, d'horloge **S**, est vue depuis c : elle garde sa valeur pendant les N instants. La sortie est `Up(c, Proj(0,W))`, la valeur après les N itérations.

```c
for (int j = 0; j < N; j++) {
    fRec0[0] = input1[i] + 0.5f * fRec0[1];
    fRec0[1] = fRec0[0];
}
output0[i] = fRec0[0];
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
Clock ::= Top                       (* le repère du haut *)
        | Derive(Clock, rate)       (* une cadence de plus *)

Sig   ::= Up(Clock, y)
        | Collect(Clock, y)
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
:   L'horloge y généralise la cadence. Elle dit sur quel repère un signal est défini ; qu'un signal du repère du haut soit constant ou change à chaque bloc reste l'affaire de la variabilité.

## Le point fixe

L'horloge est un attribut exact. Sa graine pour une variable récursive est le repère du haut, et non une valeur pessimiste comme `kSamp` pour la variabilité : un groupe écrit dans un `ondemand` n'est pas sur l'horloge échantillon. Le calcul descend tout seul, parce que toute boucle traverse une opération à horloge.

**[Q]** Garder le repère du haut, ou fournir à l'itérateur l'horloge du contexte.

# Où le code est exécuté

L'horloge d'un signal dit sur quel repère il est défini. Le compilateur choisit en plus où il émet le calcul.

- Une opération à horloge s'exécute sur son horloge, sans choix : un écho inaudible vieillit quand même. La règle `isConditionBoundary` de la branche en devient une conséquence.
- Une opération sans mémoire peut s'exécuter sur son horloge, ou sur toute horloge descendante où elle est lue. Descendre vers une sélection, c'est l'appel par nécessité ; rester sur l'ancêtre d'une subdivision, c'est la sortie des invariants de boucle.
- Les étapes des tables sont émises dans le code d'initialisation, dans leur ordre.

Une région d'horloge est un nœud du graphe de son parent. Chaque horloge a son compteur d'instants. Une sortie coûte au plus une variable qui garde la valeur choisie.

# État de l'implémentation

Rien n'est implémenté au-delà de deux étapes sans effet sur le code généré, sur la branche `ccr-faae028d-7grw0l` de `grame-cncm/faust`, au-dessus de `master-dev-certification-4`.

Étape 0 (`c3a3f794a`)
:   `ClockAlgebra` restreinte à trois niveaux (constante, bloc, échantillon), calculée à côté de la variabilité, et un test de concordance sous `FAUST_CHECK_CLOCKS`. Aucune divergence sur la suite d'impulsions (103 programmes, quatre jeux d'options) ni sur les exemples (259 programmes, environ 206 000 signaux). Code généré identique à la référence sur 2 678 compilations. Elle a été écrite quand l'horloge distinguait la constante du bloc ; dans le modèle présent les deux sont sur le repère du haut, et l'étape est à revoir.

Étape 1 (`dc1d83c1d`, `314a6dc05`)
:   Le front-end des trois primitives (mots réservés, boîtes, typage, impression, schéma). La propagation les refuse. Le parser est régénéré par bison 3.8.2 au lieu de 2.3, dans un commit séparé.

# Décisions et questions

## Prises

- Chaque horloge a pour temps ℕ ; une horloge est la suite des cadences qui y mènent.
- Le repère du haut a pour instants les étapes du programme : une par table, puis une par bloc.
- Les constantes sont des signaux du repère du haut. Aucune opération à horloge n'y est écrite.
- Les tables sont sérialisées selon leurs dépendances, par une règle déterministe.
- La sortie d'une région est un signal de l'horloge parente.
- La sortie rend la dernière valeur calculée par la région.
- Égalité structurelle des horloges.
- L'écriture de table n'est pas une opération à horloge.
- Les projections d'un groupe partagent une horloge.
- L'horloge est calculée à côté de la variabilité.
- Une branche d'horloge sur chaque opération à horloge, y compris hors région.
- Spécifier d'abord ; implémenter après la bascule de `master-dev`.

## En attente

- Les sliders sur le repère du haut, la calculabilité interdisant de les lire depuis une table.
- `Collect` comme sortie d'une table.
- Une ou deux sortes dans la signature.
- La graine des variables récursives.

## Ouvertes

Q1
:   Une sortie à valeur initiale explicite, qui serait à `Up` ce que `Prefix` est à `Mem`, pour ne pas forcer 0 dans l'intervalle d'une sortie de région.

Q2
:   `Collect` hors des tables (`vectorize`, trames FFT, `interleave`) : il faudrait une cadence constante, ou bornée.

Q3
:   `switch(C0..Ck)` : des sélections de cadences complémentaires.

Q4
:   Une cadence tantôt nulle, tantôt supérieure à 1. Le calcul la définit (ni sélection ni subdivision) ; faut-il l'accepter dans le langage ?

Q5
:   La valeur d'une horloge dans le domaine des intervalles, et la conversion de l'horizon entre le temps d'un repère et celui de son parent.

Q6
:   La vectorisation des régions de cadence constante.
