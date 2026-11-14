---
title: Un calcul d'horloges pour Faust
subtitle: Spécification, brouillon v26
date: 14 novembre 2026
document-style: article-a4
language: fr
---

::: toc+
- **Objet et statut** — dire ce que le document spécifie et où en est le travail.
- **Les repères temporels** — construire le temps sur ℕ, sans parler de signaux.
  - **Le temps d'une horloge** — une succession d'instants numérotés.
  - **Parent et cadence** — ce qu'on peut demander à une horloge.
  - **Le repère du haut** — l'horloge qui est son propre parent, de cadence 1.
  - **La remontée** — passer du temps d'une horloge à celui de son parent.
  - **Sélection et subdivision** — les deux cas remarquables.
  - **Les ancêtres** — la chaîne d'une horloge, et le treillis.
  - **Les étapes du programme** — les tables, puis les blocs.
- **Les signaux** — poser les valeurs sur les repères.
  - **Un signal et son horloge** — une valeur par instant.
  - **Voir un signal depuis un repère descendant** — composer avec la remontée.
  - **Sortir un signal vers le repère parent** — la dernière valeur calculée.
  - **La cadence est un signal** — refermer la boucle entre horloges et signaux.
- **La sémantique** — le crochet indicé par un repère, et ses règles.
- **La propagation** — la traduction des circuits en signaux, où naissent les horloges.
  - **L'horloge courante** — le paramètre que la propagation transporte.
  - **Les règles** — qui ignore l'horloge courante, qui la transmet, qui la reçoit.
  - **Les trois primitives du langage** — ondemand, upsampling, downsampling.
  - **La règle de la région** — elle prolonge l'horloge courante.
  - **La règle de la table** — elle repart du repère du haut.
  - **Ce que la propagation garantit** — un invariant, que les règles d'horloge vérifient.
  - **Un retard dans chaque région** — le même exemple déroulé trois fois.
- **Les tables** — l'initialisation comme suite d'instants du repère du haut.
  - **Une table et son repère** — un temps par table.
  - **La sortie d'une table** — les constructeurs existants.
  - **L'initialisation comme un tout** — l'ensemble ordonné des tables, sous un parent commun.
  - **La table est une région** — une construction qui reçoit des circuits.
  - **La table écrite** — l'état d'une table en lecture-écriture appartient à son contexte.
  - **Un slider dans un générateur** — sa valeur par défaut.
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
  - **Les groupes récursifs** — ils ne portent pas d'horloge, et leur horloge n'est pas un point fixe.
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

## Parent et cadence

Une horloge n'est pas définie par ce qu'elle contient, mais par ce qu'on peut en demander. On peut lui demander deux choses.

::: definition [Horloge]
Toute **horloge** c a :

- un **parent**, parent(c), qui est une horloge ;
- une **cadence**, cadence(c), qui est une fonction de ℕ dans ℕ sur le temps de son parent : cadence(c)(t) est le nombre d'instants de c qui ont lieu pendant l'instant t de parent(c).

Deux horloges sont **égales** quand elles ont le même parent et la même cadence.
:::

On note p · r l'horloge dont le parent est p et la cadence r :

```math
\mathit{parent}(p · r) = p \qquad \mathit{cadence}(p · r) = r
```

Toute horloge s'écrit ainsi : c = parent(c) · cadence(c).

## Le repère du haut

::: definition [Repère du haut]
Le **repère du haut**, noté ⊤, est l'horloge qui est son propre parent et dont la cadence vaut 1 à chaque instant :

```math
\mathit{parent}(⊤) = ⊤ \qquad \mathit{cadence}(⊤) = 1 \qquad\text{c'est-à-dire}\qquad ⊤ = ⊤ · 1
```

Toute horloge atteint ⊤ en un nombre fini de passages au parent.
:::

C'est la seule horloge qui n'est pas construite à partir d'une autre : elle amorce toutes les autres. Son temps est donné, et c'est l'hôte qui le fait avancer.

Le nombre de passages au parent qu'il faut pour atteindre ⊤ est la **profondeur** de l'horloge. Une horloge de profondeur k s'écrit ⊤ · r₁ · r₂ · … · rₖ : elle est déterminée par la suite de ses cadences.

## La remontée

La cadence dit combien d'instants ont lieu pendant chaque instant du parent. On en tire la fonction qui fait passer du temps d'une horloge au temps de son parent.

Soit c une horloge, p son parent et r sa cadence. Le nombre d'instants de c qui ont eu lieu à la fin de l'instant t de p est

```math
\mathit{fait}(t) = r(0) + r(1) + … + r(t)
```

::: definition [Remontée]
La **remontée** π de c associe à chaque instant n de c l'instant de son parent pendant lequel il a lieu : π(n) est le plus petit t tel que fait(t) > n.
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

Pendant l'instant 1 du parent il ne se passe rien. Pendant l'instant 2 ont lieu trois instants de l'horloge.

Pour le repère du haut, la cadence vaut 1 partout : fait(t) = t + 1, et la remontée est l'identité. La définition générale s'applique donc aussi à ⊤, sans cas particulier.

Si la cadence est nulle à partir d'un certain instant, l'horloge n'a qu'un nombre fini d'instants : son temps est un début de ℕ.

## Sélection et subdivision

Deux cas sont remarquables.

Sélection
:   La cadence ne vaut jamais plus de 1. Il n'y a jamais deux instants pendant le même instant du parent : la remontée est strictement croissante.

Subdivision
:   La cadence vaut toujours au moins 1. Il se passe quelque chose pendant chaque instant du parent : la remontée atteint tous les instants du parent.

Dans l'exemple ci-dessus, la cadence n'est ni l'une ni l'autre. Celle du repère du haut est les deux à la fois.

Une horloge p · 1, dont la cadence vaut 1 partout, a le même temps que p et une remontée identité. Elle n'est pas égale à p pour autant, sauf si p est le repère du haut : son parent est p, alors que celui de p est parent(p).

## Les ancêtres

Les **ancêtres** d'une horloge c sont c, parent(c), parent(parent(c)), et ainsi de suite jusqu'à ⊤. On note a ≤ c quand a est un ancêtre de c. Les ancêtres d'une horloge forment une chaîne, du repère du haut jusqu'à elle.

Pour remonter d'une horloge c à l'un de ses ancêtres a, on compose les remontées successives. On note π(c → a) cette remontée composée ; π(c → c) est l'identité.

Deux horloges quelconques ont toujours un plus proche ancêtre commun, puisque ⊤ est l'ancêtre de toutes. Si aucune n'est l'ancêtre de l'autre, elles sont **incompatibles** : leurs signaux ne se rencontrent qu'après être sortis jusqu'à cet ancêtre commun. Avec un élément « incompatible » ajouté en bas, les horloges forment un treillis dont le repère du haut est le sommet.

## Les étapes du programme

Le temps du repère du haut est la suite des **étapes** du programme : d'abord une étape par table à remplir, puis une étape par bloc. **[D]**

Avec trois tables :

```
⊤     t :   0          1          2          3        4        5   …
            table 1    table 2    table 3    bloc 0   bloc 1   bloc 2
```

Les horloges de profondeur 1 sont les **repères de base** :

| Repère de base | Sa cadence | Son temps |
| :--- | :--- | :--- |
| table i, de taille nᵢ | nᵢ à l'étape i, 0 ailleurs | nᵢ instants |
| échantillons **S** | 0 pendant les étapes des tables, puis la longueur de chaque bloc | infini |

Le premier échantillon n'a donc pas lieu pendant une étape d'initialisation : il a lieu pendant l'étape du premier bloc.

Sous chaque repère de base, on construit des régions par les mêmes dérivations. Le calcul ne distingue pas l'initialisation de l'exécution : seule change l'étape qui héberge le repère de base.

**[D]** Aucune opération qui compte le temps n'est écrite sur le repère du haut. `process` est traduit dans le repère des échantillons, chaque générateur dans le repère de sa table. Le repère du haut ne porte que des signaux sans mémoire : les constantes, les sliders, et les tables une fois remplies.

# Les signaux

## Un signal et son horloge

::: definition [Signal]
Un **signal** d'horloge c est une fonction qui donne une valeur réelle à chaque instant de c.
:::

- Une constante est un signal du repère du haut, qui prend la même valeur à chaque étape.
- Un slider est un signal du repère du haut : une valeur par étape. Pendant les étapes des tables il vaut sa valeur par défaut ; pendant l'étape d'un bloc, la valeur réglée pour ce bloc. **[D]**
- Une entrée audio est un signal d'horloge **S** : une valeur par échantillon.

## Voir un signal depuis un repère descendant

Un signal est visible dans tous les repères qui descendent du sien : il suffit de remonter.

::: definition [Vue]
Soit x un signal d'horloge a, et c une horloge dont a est un ancêtre. La **vue** de x depuis c est le signal d'horloge c qui vaut, à l'instant n, la valeur de x à l'instant π(c → a)(n).
:::

C'est une simple composition. Elle ne demande aucune opération dans le programme :

- une constante, vue de n'importe où, vaut toujours la même chose ;
- un slider vu de **S** garde la valeur de son bloc pendant tous les échantillons du bloc ;
- un slider vu du générateur d'une table y vaut sa valeur par défaut, à tous les instants ;
- une entrée audio vue d'un `ondemand` y prend la valeur qu'elle a aux échantillons où la demande est faite ;
- une entrée audio vue d'un `upsampling` par N y garde sa valeur pendant N instants.

Depuis une subdivision, on voit toutes les valeurs du signal, chacune répétée. Depuis une sélection, on ne voit que certaines d'entre elles.

## Sortir un signal vers le repère parent

Dans l'autre sens, il n'y a pas de fonction : pendant un instant du parent, une horloge peut avoir plusieurs instants, ou aucun. Sortir un signal demande donc de choisir une valeur. C'est la seule opération du calcul.

::: definition [Sortie]
Soit p une horloge, r une cadence sur p, et y un signal visible depuis p · r. La **sortie** `Up(p · r, y)` est le signal d'horloge p qui vaut, à l'instant t de p, la valeur de y au **dernier instant de p · r déjà fait** à la fin de t, c'est-à-dire à l'instant fait(t) − 1, où fait(t) = r(0) + … + r(t). S'il n'y en a encore aucun, elle vaut 0.
:::

La sortie a donc trois opérandes : l'horloge parente p, la cadence r, et le signal y. Les deux premiers sont réunis dans l'horloge p · r, dont r est la dernière cadence. Quand une horloge est nommée, par exemple c = p · r, on écrit `Up(c, y)` ; la cadence est alors la dernière de c.

La cadence est un véritable argument de la sortie : pour calculer `Up(p · r, y)` à l'instant t, il faut avoir calculé r jusqu'à t. La sortie **consulte** r, au sens de `ATTRIBUTES.md`, et en dépend dans le graphe des calculs.

Pour une sélection, la sortie maintient la valeur entre deux instants de c. Pour une subdivision, elle rend la dernière valeur de chaque groupe : le résultat des itérations faites pendant l'instant du parent. **[D]**

C'est la fonction h⁺ de la spec v5, étendue sans changement aux cadences supérieures à 1.

## La cadence est un signal

Une cadence est une fonction de ℕ dans ℕ : c'est exactement un signal entier de l'horloge parente. Dans un programme, la cadence de p · r est un signal comme un autre, entier, positif ou nul, visible depuis le parent p. Les deux notions dépendent donc l'une de l'autre : un signal a une horloge, et une horloge a pour cadence un signal.

Plusieurs choses en découlent.

- **La cadence est calculée par le programme.** Elle peut être une constante (une région périodique), dépendre d'un contrôle, d'une entrée audio, ou de la sortie d'une autre région.
- **Elle a elle-même une horloge**, ancêtre de p, et se lit depuis p par la règle de vue. Une cadence constante est un signal du repère du haut.
- **Elle a une sémantique.** Le nombre d'instants faits se calcule avec le crochet : fait(t) est la somme des valeurs de la cadence, vue de p, aux instants 0 à t de p.
- **Elle peut dépendre de la région qu'elle commande**, à travers un retard : une région peut décider de sa prochaine demande. Elle ne peut pas en dépendre dans le même instant, ce serait un cycle sans retard.
- **Les cadences données par l'hôte sont des signaux aussi.** La longueur de chaque bloc et la taille de chaque table sont des signaux du repère du haut.
- **Elle est transformée comme tout signal.** Une horloge contient ses cadences ; une transformation qui réécrit les signaux réécrit donc aussi les horloges.

**[D] Égalité.** Deux horloges sont égales quand elles ont le même parent et le même signal de cadence, comparé par identité d'arbre après mise en forme normale.

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
:   C'est la formule habituelle, dans le repère p · r que porte le retard.

```math
⟦\mathsf{Delay}(p · r, x, d)⟧_{p · r}(n) = ⟦x⟧_{p · r}(n - ⟦d⟧_{p · r}(n)) \qquad \text{pour } n ≥ 0
```

Vue
:   Un signal d'horloge a, regardé depuis un repère descendant c, se lit en remontant. La remontée se calcule avec les cadences qui séparent a de c.

```math
⟦s⟧_c(n) = ⟦s⟧_a(π(c → a)(n))
```

Sortie
:   La cadence r est un signal : fait(t) se calcule en la lisant dans p.

```math
⟦\mathsf{Up}(p · r, y)⟧_p(t) = ⟦y⟧_{p · r}(\mathit{fait}(t) - 1)
\qquad\text{avec}\qquad
\mathit{fait}(t) = ⟦r⟧_p(0) + ⟦r⟧_p(1) + … + ⟦r⟧_p(t)
```

Seules les deux dernières règles sont nouvelles. Ce sont les deux seuls endroits où l'indice du crochet change, et les deux seuls où interviennent les cadences : la vue par la remontée, la sortie par le nombre d'instants faits.

Pour que la première règle soit cohérente avec la vue, on prolonge la remontée : un instant négatif d'un repère remonte sur un instant négatif de son parent. La sortie vaut alors bien 0 tant que fait(t) = 0.

**Voir puis retarder n'est pas retarder puis voir.** Un retard d'horloge c, regardé depuis un repère plus profond, reste calculé dans c : c'est la règle de vue qui s'applique, pas celle du retard. L'horloge portée par le retard fixe le repère où l'on compte.

**Un slider retardé.** Dans `process`, `slider'` est `Mem(S, u)` : le slider u est sur le repère du haut, le retard sur celui des échantillons. À l'échantillon n, le retard lit u à l'étape qui contient l'échantillon n − 1. Avec des blocs de 4 échantillons, u valant a puis b :

```
échantillon      n :  0  1  2  3  4  5  6  7
u vu de S          :  a  a  a  a  b  b  b  b
Mem(S, u)          :  0  a  a  a  a  b  b  b
```

C'est un retard d'un échantillon, non d'un bloc : l'horloge de l'argument dit où il est défini, l'horloge du retard dit où l'on compte.

# La propagation

Les horloges ne sont pas déduites après coup : elles naissent pendant la **propagation**, la traduction d'un circuit Faust en signaux. La propagation transporte une horloge courante et la donne à tout ce qui compte le temps.

## L'horloge courante

La traduction d'un circuit C reçoit, en plus de ses signaux d'entrée, une **horloge courante** k. On la note en indice :

```math
⟦C⟧_k(x_1, …, x_n) = (y_1, …, y_m)
```

`process` est propagé avec l'horloge des échantillons, **S** = ⊤ · count.

## Les règles

Les circuits qui ne comptent pas le temps ignorent l'horloge courante.

```math
⟦n⟧_k() = (n) \qquad ⟦\_⟧_k(x) = (x) \qquad ⟦!⟧_k(x) = () \qquad ⟦⋆⟧_k(x, y) = (⋆(x, y))
```

Un slider se traduit par lui-même : c'est un signal du repère du haut, quelle que soit l'horloge courante.

Les compositions la transmettent, inchangée, à leurs deux branches.

```math
⟦A : B⟧_k(x) = ⟦B⟧_k(⟦A⟧_k(x)) \qquad ⟦A , B⟧_k(x, y) = (⟦A⟧_k(x),\ ⟦B⟧_k(y))
```

Il en va de même de `<:` et de `:>`.

Les circuits qui comptent le temps la reçoivent.

```math
⟦@⟧_k(x, d) = (\mathsf{Delay}(k, x, d)) \qquad ⟦'⟧_k(x) = (\mathsf{Mem}(k, x))
```

La composition récursive écrit sa boucle de retour avec l'horloge courante. Pour A ~ B, avec W le groupe récursif créé :

```math
⟦A \sim B⟧_k(x) = (y) \quad\text{où}\quad (z) = ⟦B⟧_k(\mathsf{Mem}(k, W)), \quad (y) = ⟦A⟧_k(z, x), \quad W := (y)
```

Un groupe récursif est donc créé sous une horloge courante connue : celle du `Mem` qui ferme sa boucle.

## Les trois primitives du langage

| Primitive | Cadence | Nature | Fréquence vue à l'intérieur |
| :--- | :--- | :--- | :--- |
| `ondemand(P)(h)` | h, qui vaut 0 ou 1 | sélection | SR |
| `downsampling(P)(N)` | 1 un instant sur N, 0 sinon | sélection | SR / N |
| `upsampling(P)(N)` | N | subdivision | N · SR |

Ce sont trois vues de la même construction. `downsampling(P)(N)` est un `ondemand` dont la demande est un compteur modulo N écrit sur l'horloge courante. La fréquence d'échantillonnage appartient à la primitive, pas à l'horloge : la propagation la transporte à côté de l'horloge courante.

## La règle de la région

Le premier signal d'entrée devient la cadence, et le corps est propagé avec l'horloge courante prolongée par cette cadence :

```math
⟦\mathsf{region}(C)⟧_k(r, x_1, …, x_n) = (\mathsf{Up}(k · r, y_1), …, \mathsf{Up}(k · r, y_m))
\quad\text{où}\quad (y_1, …, y_m) = ⟦C⟧_{k · r}(x_1, …, x_n)
```

Trois choses s'y passent :

1. la cadence r, un signal de l'horloge k, forme la nouvelle horloge k · r ;
2. le corps C est propagé avec cette horloge courante : tous ses retards la recevront ;
3. chaque sortie est ramenée sur l'horloge k par une sortie `Up`.

Les autres entrées passent telles quelles : elles sont sur une horloge ancêtre de k · r, donc visibles. Il en va de même des constantes, des sliders et des signaux extérieurs capturés.

La sortie d'une région est toujours un signal de l'horloge où la région est écrite. Deux régions voisines ne se lisent donc jamais directement. **[D]**

## La règle de la table

**[D] Une table est une construction qui reçoit des circuits.** Elle n'est pas une primitive qui reçoit des signaux : sa taille et son générateur sont ses paramètres, comme le corps d'un `ondemand`, et elle rend un circuit.

| Construction | Paramètres | Circuit construit |
| :--- | :--- | :--- |
| `rdtable(n, G)` | la taille n, le générateur G (aucune entrée, une sortie) | une entrée, l'indice de lecture ; une sortie |
| `rwtable(n, G)` | les mêmes | trois entrées, l'indice d'écriture, la valeur écrite, l'indice de lecture ; une sortie |

L'écriture habituelle reste valable : appliquer des arguments à un circuit, c'est les brancher sur ses entrées. `rdtable(n, G, i)` se lit i : `rdtable(n, G)`, et `rwtable(n, G, w, x, i)` se lit (w, x, i) : `rwtable(n, G)`. Ce qui disparaît est la forme où la taille et le générateur arrivent eux-mêmes par des fils.

**[D] Le générateur est traduit sous l'horloge de la table, qui dérive toujours du repère du haut**, quelle que soit l'horloge courante. La propagation le traduit directement sous cette horloge : il n'y a jamais d'horloge à changer après coup.

Le générateur traduit devient `Gen(T, g)`, la sortie qui collecte ses n valeurs : un signal du repère du haut. Deux opérations distinctes en font une table.

Pour une table en lecture seule, `ROTbl` (*read-only table*) :

```math
⟦\mathsf{rdtable}(n, G)⟧_k(i) = (\mathsf{RDTbl}(\mathsf{ROTbl}(n, \mathsf{Gen}(T, g)),\ i))
\quad\text{où}\quad (g) = ⟦G⟧_T(), \quad T = ⊤ · τ
```

τ est la cadence de la table : n pendant l'étape de la table, 0 ailleurs. Seul l'indice de lecture vient du contexte, et la lecture est une opération sans mémoire. Si la table est lue dans un `ondemand`, la table et son contenu sont donc calculés en dehors de la région.

Pour une table en lecture-écriture, `WRTbl`. Les trois entrées viennent du contexte, et la table reçoit l'horloge courante, comme `@` et `'` la reçoivent :

```math
⟦\mathsf{rwtable}(n, G)⟧_k(w, x, i) = (\mathsf{RDTbl}(\mathsf{WRTbl}(k, n, \mathsf{Gen}(T, g), w, x),\ i))
\quad\text{où}\quad (g) = ⟦G⟧_T(), \quad T = ⊤ · τ
```

Deux `rwtable` propagées sous deux horloges courantes différentes donnent deux arbres, donc deux tables, même si leurs trois entrées sont identiques. Elles ont le même générateur `Gen(T, g)`, traduit une seule fois. **[D]**

La règle de la région et celle de la table sont les deux seules qui changent l'horloge courante. La région la prolonge ; le générateur d'une table repart du repère du haut.

L'étape d'une table est attribuée quand la propagation de son générateur s'achève. Les tables que ce générateur lit ont alors déjà la leur : la numérotation suit les dépendances, et elle est déterministe.

Une même table en lecture seule, écrite à plusieurs endroits du programme, est propagée une seule fois : même taille et même générateur donnent la même horloge et le même arbre.

## Ce que la propagation garantit

Dans un programme propagé sous l'horloge courante k, tout signal a pour horloge un ancêtre de k. Une table lue dans ce programme est un signal du repère du haut, ancêtre de tout. Les règles d'horloge données plus loin ne servent donc pas à trouver les horloges : elles vérifient ce que la propagation a construit, et ce que chaque transformation doit préserver.

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

## Une table et son repère

Le remplissage d'une table de taille n est le calcul d'un signal sur un repère de base qui a n instants, tous pendant une même étape du repère du haut. Le générateur y avance d'un pas par instant : « les n premiers instants d'un signal » se lit littéralement.

Chaque table a son propre repère. Deux raisons l'imposent : chaque générateur repart de son instant 0 et s'arrête à sa propre taille, et une table qui en lit une autre a besoin qu'elle soit complète.

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

## La sortie d'une table

Une sortie `Up` ne garderait que la dernière des n valeurs. La table les garde toutes. Quatre opérations se partagent les rôles :

| Opération | Lecture dans le calcul |
| :--- | :--- |
| `Gen(T, g)` | la sortie qui collecte : g est le signal du générateur, sur le repère T de la table ; `Gen(T, g)` est le signal du repère du haut qui vaut, à partir de l'étape de la table, le tableau des n valeurs de g |
| `ROTbl(n, gen)` | la table en lecture seule : ce tableau, qui ne change plus |
| `WRTbl(k, n, gen, w, x)` | la table en lecture-écriture : une mémoire sur l'horloge k, qui part de ce tableau et reçoit les écritures |
| `RDTbl(table, index)` | une opération sans mémoire : indexer la table |

`Gen` est à la table ce que `Up` est à la région : `Up(p · r, y)` rend la dernière valeur, `Gen(⊤ · τ, g)` les rend toutes.

Le compilateur a déjà les constructeurs `sigGen(g)`, `sigRDTbl(table, index)` et `sigWRTbl(size, gen, wi, ws)`. Ce dernier sert aujourd'hui aux deux tables, celle en lecture seule étant sa forme sans écriture. Le calcul leur donne deux noms, `ROTbl` et `WRTbl`, parce que ce sont deux opérations : la première est un signal du repère du haut, la seconde une mémoire sur l'horloge courante. `sigGen` et `sigWRTbl` gagnent une horloge.

La taille de la table est la cadence de son repère : elle figure donc deux fois, dans τ et dans l'argument n. Cette redondance vient du constructeur existant.

## L'initialisation comme un tout

L'initialisation est un seul objet : l'ensemble des tables du programme, ordonné par leurs dépendances, sous leur parent commun, le repère du haut. **[D]**

- **Les tables sont recensées sur tout le programme**, qu'elles apparaissent dans `process` ou dans le générateur d'une autre table. Elles sont toutes au même niveau : aucune n'est à l'intérieur d'une autre.
- **Elles sont ordonnées une fois**, selon leurs dépendances. Chaque table reçoit une étape du repère du haut, postérieure à celles des tables qu'elle lit : elle la reçoit quand la propagation de son générateur s'achève. Une table ne lit donc que le passé, et l'exécution vient après toutes.
- **Elles sont accessibles les unes aux autres par leur parent commun.** Une table remplie est un signal du repère du haut : elle est visible de tous les repères, y compris de celui d'une table postérieure et de toute région de l'exécution.
- **Une table est identifiée par ce qu'elle est**, sa taille et son générateur. Deux lectures de la même table désignent le même objet, rempli une seule fois.

Deux conditions accompagnent la sérialisation :

- le sens du programme ne dépend pas de l'ordre choisi entre deux tables indépendantes, puisqu'elles ne se lisent pas ;
- l'ordre doit être fixé par une règle, pour que le compilateur reste déterministe.

Le compilateur actuel ne procède pas ainsi : il compile une table dans le conteneur du générateur qui la lit. Sur `master-dev-certification-4`, une table dont le générateur lit une autre table est mal compilée (constaté le 14 novembre : en `cpp` la table lue n'est jamais remplie, en `ocpp` le code émis ne s'édite pas). Un même générateur pour deux tables de tailles différentes est en revanche correct : une classe par générateur, une instance par table.

## La table est une région

La difficulté venait d'un défaut de conception. `rdtable` est aujourd'hui une primitive à trois signaux : quand la propagation l'atteint, le générateur a déjà été traduit avec l'horloge courante, et il est le même arbre que le même circuit utilisé comme signal ordinaire. Un nœud aurait alors deux exécutions, dans deux boucles, avec deux états.

La table est donc traitée comme un `ondemand` de sa partie générative (voir la règle de la table, dans la propagation) :

| | `ondemand(C)(h)` | table de taille n, générateur G |
| :--- | :--- | :--- |
| corps | un circuit, traduit sous une horloge dérivée | un circuit, traduit sous une horloge dérivée |
| horloge parente | l'horloge courante | le repère du haut, toujours |
| cadence | h, un signal d'entrée | n pendant l'étape de la table, 0 ailleurs |
| entrées du corps | celles du circuit | aucune |
| sortie | `Up` : la dernière valeur | `Gen` : toutes les valeurs |

Un générateur qui lirait un signal de l'exécution, une entrée audio par exemple, n'a pas besoin d'une vérification à part : ce signal est sur une horloge incompatible avec celle de la table, et les règles d'horloge le refusent.

## La table écrite

Une table en lecture-écriture a un état : son contenu change au fil des écritures. Cet état appartient au contexte où elle est écrite. Deux `rwtable` identiques placées dans deux `ondemand` sont deux tables, comme deux retards identiques y sont deux retards.

`WRTbl(k, n, gen, w, x)` réunit donc deux choses, d'horloges différentes :

- son **contenu initial**, `gen` = `Gen(T, g)` : un signal du repère du haut, le même arbre pour toutes les tables de ce générateur ;
- sa **mémoire**, qui part de ce contenu et reçoit les écritures : elle vit sur l'horloge k que porte l'opération.

La table écrite est à son contenu initial ce que `Prefix(k, x0, x)` est à sa valeur de départ x0.

La table en lecture seule n'a pas de mémoire qui évolue. Elle est une opération différente, `ROTbl(n, gen)`, qui ne porte pas d'horloge : ses deux arguments sont des signaux du repère du haut, elle en est donc un aussi.

Réécrire la même valeur au même index est sans effet, mais cela ne suffit pas à rendre l'écriture indépendante de l'horloge. Dans un `ondemand`, la table n'est écrite qu'aux instants de la demande, avec les valeurs vues à ces instants : si la valeur écrite est un slider, la table garde celle de la dernière demande, non la valeur courante. Au niveau principal, en revanche, voir un slider depuis les échantillons ne perd rien, et l'on peut exécuter l'écriture une fois par bloc : c'est une optimisation, celle que fait aujourd'hui la variabilité.

## Un slider dans un générateur

Un slider est visible depuis le repère d'une table, et il y vaut sa valeur par défaut : le générateur le voit comme une constante. La table est donc calculable à l'initialisation, et un réglage fait ensuite ne la modifie pas. Le compilateur actuel refuse ce programme (`checkInit failed`) ; ce serait une extension. **[D]**

# Les règles d'horloge

## Trois sortes d'opérations

| Sorte | Exemples | Horloge du résultat |
| :--- | :--- | :--- |
| **sans mémoire** | arithmétique, `select2`, `RDTbl`, `ROTbl` | la plus longue de celles des arguments |
| **à horloge** | `Mem`, `Delay`, `Prefix`, `Fir`, `Iir`, `Irm`, `Waveform`, `WRTbl`, fonction étrangère sans argument | l'horloge p · r qu'elle porte |
| **sortie** | `Up` ; pour une table, `Gen` | le parent p de l'horloge p · r qu'elle porte |

Une opération est **à horloge** quand son résultat dépend du nombre d'instants écoulés. Un retard de 1 sur une horloge n'est pas un retard de 1 sur une autre :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes
```

**[D] Une opération porte une horloge quand cette horloge ne se déduit pas de ses arguments.**

| Opération | Pourquoi l'horloge ne se déduit pas |
| :--- | :--- |
| `Delay(k, x, d)` | x peut venir d'un ancêtre de k : une constante retardée dans un `ondemand` |
| `WRTbl(k, n, gen, w, x)` | de même : w et x peuvent être des sliders |
| `Up(p · r, y)` | la cadence r n'est nulle part ailleurs |
| `Gen(T, g)` | g peut être une constante, sur le repère du haut |

`ROTbl(n, gen)` n'en porte pas : son horloge est celle de ses arguments, le repère du haut. La condition « aucune opération à horloge sur le repère du haut » reste ainsi sans exception.

**[D] La cadence est visible.** Une opération à horloge s'écrit avec son horloge sous la forme parent · cadence : `Delay(p · r, x, d)`, `Mem(p · r, x)`, comme la sortie `Up(p · r, y)`. Deux conséquences :

- au niveau principal, un retard s'écrit `Delay(⊤ · count, x, d)`, la cadence étant la longueur des blocs ;
- le repère du haut s'écrivant lui-même ⊤ · 1, la règle « aucune opération à horloge sur le repère du haut » ne découle pas de l'écriture : c'est une condition des règles d'horloge.

La cadence ne joue pas le même rôle dans les deux cas. Dans une sortie, elle entre dans le calcul de la valeur. Dans une opération à horloge, elle dit seulement **quand** l'opération s'exécute : sa valeur, dans son propre repère, ne dépend que du nombre d'instants écoulés.

Quand une horloge est nommée, par exemple **S** = ⊤ · count ou c = p · r, on écrit `Delay(S, x, d)` ou `Mem(c, x)` ; la cadence est alors la dernière de l'horloge.

La table écrite `WRTbl` en est une : son contenu dépend des instants où l'on écrit. La table en lecture seule `ROTbl` n'en est pas une. **[D]**

## Les règles

On note ⊢ s : c pour « s est un signal d'horloge c ».

```inference (constante)
---
⊢ k : ⊤
```

```inference (slider)
---
⊢ u : ⊤
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
⊢ s1 : c1; ⊢ s2 : c2; c1 ≤ p · r; c2 ≤ p · r; p · r ≠ ⊤
---
⊢ Delay(p · r, s1, s2) : p · r
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

Pour les attributs de valeur (nature, booléanité, intervalle), `Up(p · r, y)` porte y, et la cadence r n'y entre pas :

- si la cadence vaut au moins 1 au premier instant du parent : la valeur de y. C'est toujours le cas d'une subdivision ;
- sinon : la valeur de y **unie à** 0, ce que vaut la sortie tant que c n'a pas eu d'instant.

La sortie porte l'union avec la valeur initiale, exactement comme le retard dans `FIXPOINT-SPEC.md` (Y@n = Y ⊔ α(0)).

Conséquence à garder en tête : une valeur sortie d'un `ondemand` a 0 dans son intervalle, ce qui pèse sur la certification d'un retard ou d'un index qui en dépend. Ce 0 est accepté : la sortie n'a pas de valeur initiale explicite. **[D]**

Pour les attributs de temporalité, la sortie consulte y et r : leurs deux temporalités entrent dans celle du résultat.

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
:   avec r = 1 partout, c a le même temps que p et la remontée est l'identité : `Up(p · 1, y)` = y, et une opération d'horloge p · 1 vaut la même opération d'horloge p. Avec r = 0 partout, c n'a aucun instant et toute sortie vaut 0.

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

**[D] L'horloge est une structure fixe, dont les cadences sont des `T`.** Une horloge n'est pas un signal, et sa structure ne dépend pas de l'interprétation : c'est toujours un parent et une cadence. Ce qui varie avec `T`, c'est seulement la représentation de la cadence, qui est un signal. La signature garde donc son unique paramètre, et l'horloge y est une structure définie une fois :

```cpp
template <typename T> struct Clock {
    Clock<T> parent() const;
    T        cadence() const;
    bool     isTop() const;      // parent() == *this, cadence() == 1
};
```

Les opérations à horloge reçoivent une horloge de plus :

```cpp
virtual T Delay(const Clock<T>& clk, const T& x, const T& d) const = 0;
virtual T Up(const Clock<T>& clk, const T& y) const = 0;
```

Le repère du haut et la dérivation ne sont pas des opérations que chaque algèbre interprète : ce sont les constructeurs de la structure, les mêmes pour toutes. Dans l'arbre de signaux, ils sont des nœuds :

```adt
Clock ::= Top                       (* le repère du haut : Top = Derive(Top, 1) *)
        | Derive(Clock, rate)       (* l'horloge de ce parent et de cette cadence *)

Sig   ::= Up(Clock, y)              (* Clock = Derive(parent, rate) : la cadence est dans l'horloge *)
        | Gen(Clock, y)             (* la sortie d'une table : toutes les valeurs du générateur y *)
        | ROTbl(n, gen)             (* la table en lecture seule : sans horloge *)
        | WRTbl(Clock, n, gen, wi, ws)   (* la table en lecture-écriture, sur l'horloge où elle est écrite *)
        | Mem(Clock, x)             (* de même pour les opérations à horloge *)
        | Delay(Clock, x, d)
        | Prefix(Clock, x0, x)
        | Fir(Clock, x, coefs)
        | Iir(Clock, x, coefs)
        | Irm(Clock, x, c)
        | Waveform(Clock, w)
```

Ce choix a trois raisons.

- Une horloge n'est pas un `T` : `Clock<T>` et `T` sont deux types distincts, et intervertir une horloge et un signal est une erreur de compilation. Aucune algèbre n'a à inventer la nature ou l'intervalle d'une horloge.
- La structure n'est pas un second paramètre libre : `FaustAlgebra<T>` garde sa forme, et seules les opérations qui comptent le temps changent.
- La signature a déjà des structures fixes remplies de `T` : `Fir` et `Sum` prennent un vecteur de `T`.

Chaque algèbre reçoit l'horloge avec ses cadences déjà interprétées dans son domaine :

| Algèbre | Ce qu'elle reçoit | Ce qu'elle en fait |
| :--- | :--- | :--- |
| arbres | les arbres des cadences | elle rebâtit le terme d'horloge |
| intervalles | les intervalles des cadences | les bornes pour convertir le temps d'un repère en temps de son parent |
| nature, booléanité | les natures des cadences | rien |

L'adaptateur évalue chaque cadence de l'horloge avant d'appeler l'opération, comme il le fait déjà pour les bornes d'un slider, rangées dans une liste imbriquée.

Une algèbre abstraite ne peut pas reconnaître que deux horloges sont la même : deux cadences différentes peuvent avoir le même intervalle. L'identité d'une horloge n'existe qu'au niveau des arbres. Le calcul de l'horloge d'un signal, qui en a besoin, lit le nœud lui-même.

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

## Les groupes récursifs

**[D]** Un groupe récursif ne porte pas d'horloge. C'est le `Mem` qui ferme sa boucle qui la porte. Les groupes récursifs restent ainsi une notion générale des arbres, indépendante des signaux Faust et de leurs horloges.

L'horloge des projections d'un groupe se déduit de ses définitions : c'est la plus profonde de leurs horloges. Ce calcul n'est pas un point fixe. Dans une définition, toute référence au groupe passe par une opération à horloge, et l'horloge d'une telle opération ne dépend pas de celle de ses arguments : l'horloge du groupe ne peut donc pas influencer celle de sa propre définition. Quelle que soit l'horloge que l'on suppose au groupe pour évaluer ses définitions, le résultat est le même, et une seule évaluation suffit.

Le résultat est l'horloge courante sous laquelle la propagation a créé le groupe, dès que la boucle de retour est effectivement lue. Si le moteur de calcul d'attributs demande une valeur de départ pour les groupes récursifs, le repère du haut convient ; la valeur de départ de la variabilité, transposée en « horloge des échantillons », ne convient pas pour un groupe écrit dans le générateur d'une table.

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

- Chaque horloge a pour temps ℕ. Une horloge a un parent et une cadence ; le repère du haut est son propre parent, de cadence 1.
- Le repère du haut a pour instants les étapes du programme : une par table, puis une par bloc.
- Les constantes et les sliders sont des signaux du repère du haut. Aucune opération à horloge n'y est écrite.
- Pendant les étapes des tables, un slider vaut sa valeur par défaut.
- La cadence est visible dans la sortie et dans les opérations à horloge, qui s'écrivent avec parent · cadence.
- Dans la signature algébrique, l'horloge est une structure fixe `Clock<T>` dont les cadences sont des `T` ; la signature garde un seul paramètre.
- L'initialisation est traitée comme un tout : l'ensemble des tables, recensées sur tout le programme, ordonnées selon leurs dépendances par une règle déterministe, sous le repère du haut.
- Les horloges naissent à la propagation, qui transporte une horloge courante. Deux règles la changent : la région la prolonge, la table repart du repère du haut.
- Une table est une construction qui reçoit des circuits, sa taille et son générateur, et non une primitive qui reçoit des signaux. `rdtable(n, G)` rend un circuit à une entrée, `rwtable(n, G)` un circuit à trois entrées. La forme où la taille et le générateur arrivent par des fils disparaît.
- L'horloge du générateur dérive toujours du repère du haut ; une région qui lit ou écrit une table ne porte que sur la lecture et l'écriture.
- La sortie d'une table est `Gen(T, g)`, qui collecte toutes les valeurs du générateur ; la taille de la table est la cadence de son repère T.
- Deux opérations pour les deux tables : `ROTbl(n, gen)`, la table en lecture seule, un signal du repère du haut, sans horloge ; `WRTbl(k, n, gen, w, x)`, la table en lecture-écriture, une opération à horloge.
- Une opération porte une horloge quand cette horloge ne se déduit pas de ses arguments.
- La sortie d'une région est un signal de l'horloge parente.
- La sortie rend la dernière valeur calculée par la région.
- Tant que la région n'a rien calculé, la sortie vaut 0. Il n'y a pas de sortie à valeur initiale explicite, qui serait à `Up` ce que `Prefix` est à `Mem` : `prefix` n'est presque jamais utilisé, et une telle sortie n'est pas indispensable.
- Égalité structurelle des horloges.
- La table écrite d'une `rwtable` porte l'horloge courante ; son contenu initial est la sortie `Gen(T, g)` de son générateur. Cela remplace la décision antérieure, selon laquelle l'écriture de table suivait l'horloge de ses arguments.
- Les projections d'un groupe partagent une horloge, la plus profonde de celles de ses définitions. Un groupe récursif ne porte pas d'horloge : c'est le `Mem` qui ferme sa boucle qui la porte.
- L'horloge est calculée à côté de la variabilité.
- Une branche d'horloge sur chaque opération à horloge, y compris hors région.
- Spécifier d'abord ; implémenter après la bascule de `master-dev`.

## En attente

- Rien pour l'instant.

## Ouvertes

Q1
:   Une sortie qui collecte, comme celle d'une table, hors de l'initialisation (`vectorize`, trames FFT, `interleave`) : il faudrait une cadence constante, ou bornée.

Q2
:   `switch(C0..Ck)` : des sélections de cadences complémentaires.

Q3
:   Une cadence tantôt nulle, tantôt supérieure à 1. Le calcul la définit (ni sélection ni subdivision) ; faut-il l'accepter dans le langage ?

Q4
:   La valeur d'une horloge dans le domaine des intervalles, et la conversion de l'horizon entre le temps d'un repère et celui de son parent.

Q5
:   La vectorisation des régions de cadence constante.
