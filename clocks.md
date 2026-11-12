# Un calcul d'horloges pour Faust

**[Brouillon v4 — document de travail, 12 novembre 2026]**

Objet : poser la théorie des horloges qui servira de base à la réimplémentation de
`ondemand`, `upsampling` et `downsampling` sur `master-dev-certification-4`.
Ce document ne spécifie que la logique des horloges ; il ne décrit pas encore
l'implémentation. Les propositions notées **[P]** sont des choix de conception
soumis à discussion, les points notés **[Q]** sont des questions ouvertes, les points
notés **[D]** sont décidés.

Changements depuis la v2 : **discipline de chaîne**. Les arguments d'un calcul sans
mémoire ont toujours des horloges totalement ordonnées, et l'horloge du résultat est
celle de l'un d'eux. Pour cela la sortie d'une région est toujours ramenée sur
l'horloge parente, et une constante n'a pas d'horloge propre.

Sources : `spec.md` (ondemand v5), les documents Expressive E, les slides IFC-24, le
code de `master-dev-ocpp-od-fir-2-FIR20` (dernière implémentation à horloges) et celui
de `master-dev-certification-4` (commit `106dda74a`). L'inventaire a été fait sur
`-certification-3` ; `-4` en est le rebasage sur `master-dev`, et le code du
compilateur n'en diffère que par les backends Rust et Julia et trois lignes de
`dag_instructions_compiler.cpp`.

## 1. Constat : l'horloge est déjà là, sous quatre déguisements

`certification-4` n'a aucun constructeur d'horloge, mais quatre mécanismes y
répondent déjà à la question « à quels instants ce signal est-il calculé ? » :

| Mécanisme existant | Question à laquelle il répond | Où |
|---|---|---|
| Variabilité `kKonst`/`kBlock`/`kSamp` et calculabilité `kComp`/`kInit`/`kExec` | init, une fois par bloc, ou à chaque échantillon ? | `VariabilityAlgebra`, `ComputabilityAlgebra` (`signals/sigattributes.cpp`) |
| Annotation de condition (`conditionAnnotation`, `Statement(cond, …)`) | ce nœud n'est calculé que si la garde est vraie | `generator/compile_scal.cpp`, `tlib/dcond.hh` |
| Frontière d'affichage (`computeDisplayFrontier`, `controlCS`) | les cônes des bargraphs sont évalués une fois par bloc, sur les valeurs de fin de bloc | `generator/compile_scal.cpp` |
| Générateurs de tables (`sigGen`) | un signal entier calculé hors temps réel, à l'initialisation | tables, waveforms |

L'ancienne implémentation (`FIR20`) ajoutait un cinquième mécanisme, séparé des
quatre autres : l'environnement d'horloge, porté par des nœuds enveloppes
`sigClocked(env, s)`.

La thèse de ce document est que ces cinq mécanismes sont des instances d'une seule
notion, et qu'un seul calcul peut les couvrir.

## 2. Instants et horloges

### 2.1 Les instants

On se donne un ensemble $\mathbb{T}$ d'**instants**, totalement ordonné. Une
**horloge** est une partie de $\mathbb{T}$ ; ses éléments sont ses **tops**. Un signal
d'horloge $H$ est une fonction $H \to \mathbb{R}$.

Les horloges forment donc un treillis pour l'inclusion, avec l'union et
l'intersection. $H_1 \subseteq H_2$ se lit « $H_1$ est plus rare que $H_2$ ».

### 2.2 Les horloges naturelles

Elles sont imposées par l'hôte, pas par le programme.

| Horloge | Tops |
|---|---|
| $\mathbf{S}$ | les échantillons $0, 1, 2, \ldots$ |
| $\mathbf{B}$ | les débuts de blocs |
| $\mathbf{B}'$ | les fins de blocs (dernier échantillon de chaque bloc) |

On a $\mathbf{B} \subset \mathbf{S}$ et $\mathbf{B}' \subset \mathbf{S}$. Les sliders
sont des signaux sur $\mathbf{B}$, les entrées audio des signaux sur $\mathbf{S}$.
Toutes les horloges naturelles ont un top à l'instant $0$.

Une **constante** n'a pas d'horloge propre : elle prend celle du calcul qui l'utilise.
On note $\bot$ cette absence d'horloge, avec $\bot \subseteq H$ pour toute horloge $H$.
Cela couvre les valeurs connues à la compilation et celles calculées à
l'initialisation (`SR`, tailles de tables). On sait que
$\mathbf{B} \subset \mathbf{S}$ sans savoir quel sous-ensemble : la sémantique d'un
programme ne doit pas en dépendre (voir 4.5).

La compilation n'est pas une horloge. Un calcul fait par le compilateur relève de
l'étagement, pas d'un instant d'exécution.

### 2.3 Les horloges dérivées

Une horloge dérivée est construite à partir d'une horloge parente $p$ et d'un
**signal de cadence** $r$, entier positif ou nul, lu sur $p$ :

$$p \triangleright r = \{\tau \cdot \tfrac{j}{r(\tau)} \mid \tau \in p,\ 0 \le j < r(\tau)\}$$

$r(\tau)$ est le nombre de tops de la nouvelle horloge attachés au top $\tau$ de $p$.
L'instant $\tau \cdot q$, pour une fraction $q \in [0,1[$, est situé entre $\tau$ et
le top suivant de $p$, à la proportion $q$ de l'intervalle. Les instants de
$\mathbb{T}$ sont ainsi des suites finies de fractions, ordonnées lexicographiquement.

**[D] Convention « début ».** $\tau \cdot 0 = \tau$ : le premier sous-instant *est*
l'instant parent.

Deux cas utiles :

- $r \le 1$ : **sélection**. $p \triangleright r \subseteq p$.
- $r \ge 1$ : **subdivision**. $p \subseteq p \triangleright r$, grâce à la convention
  « début ».

| Primitive | Cadence $r$ | Relation à $p$ | Code produit par `FIR20` |
|---|---|---|---|
| `ondemand(P)(h)` | $h \in \{0,1\}$ | $\subseteq p$ | `if (h) {…}` |
| `downsampling(P)(N)` | $[t \bmod N = 0]$ | $\subseteq p$ | `if (cpt % N == 0) {…}` |
| `upsampling(P)(N)` | $N$ | $\supseteq p$ | `for (j < N) {…}` |

Les trois primitives sont donc une seule construction.

**[D] Égalité.** Deux horloges dérivées sont égales si elles ont même parent et même
signal de cadence, comparé par identité d'arbre après mise en forme normale.
L'identité est *structurelle* : deux `ondemand` pilotés par le même $h$ ont la même
horloge. Deux écritures différentes d'une même cadence peuvent rester distinctes ; on
y perd une simplification, pas la correction.

### 2.4 Le temps différé

Le temps différé précède le temps réel : ses instants sont antérieurs à l'échantillon
$0$. Le remplissage d'une table de taille $n$ est un signal sur une horloge finie
$\mathbf{G}_n$ de $n$ tops, tous situés avant $0$. C'est la même construction qu'une
subdivision, sur un axe qui n'est pas celui des échantillons.

Seule la sortie diffère : la table *collecte* les $n$ valeurs au lieu de n'en lire
qu'une. Elle est complète à l'instant $0$, donc pour tous les lecteurs en temps réel.
Les calculs d'initialisation s'exécutent eux aussi en temps différé ; leur résultat
est une constante pour le temps réel.

### 2.5 La fréquence nominale

Chaque horloge dérivée déclare un rapport $\rho$ : $N$ pour un `upsampling`, $1/N$
pour un `downsampling`, $1$ pour un `ondemand`. Il n'affecte pas les tops. Il donne la
fréquence d'échantillonnage vue à l'intérieur : $\mathrm{SR}_c = \rho \cdot \mathrm{SR}_p$,
comme dans `FIR20`.

## 3. La règle de lecture

### 3.1 Définition

La valeur d'un signal $x$ d'horloge $H$, **lue** à un instant $t$ quelconque de
$\mathbb{T}$, est sa valeur au dernier top de $H$ qui ne dépasse pas $t$ :

$$x\lfloor t \rfloor = x(\max\{u \in H \mid u \le t\}) \qquad \text{et } 0 \text{ s'il n'y a pas encore eu de top}$$

C'est l'instant le plus proche qui respecte la causalité. La règle est définie pour
toute paire d'horloges, comparables ou non. Le « $\le$ » admet la lecture au même
instant ; un cycle de dépendances doit donc contenir un retard, comme aujourd'hui.

### 3.2 Les trois cas

Soit un calcul fait sur $H_0$, qui lit un argument d'horloge $H_i$ :

| Cas | Ce que fait la lecture | Perte |
|---|---|---|
| $H_i \subseteq H_0$ (argument plus rare) | maintien de la dernière valeur ($\uparrow$ de la spec v5) | non |
| $H_i \supseteq H_0$ (argument plus dense) | échantillonnage ($\downarrow$ de la spec v5) | oui |
| incomparables | maintien puis échantillonnage | oui |

**Compatibilité.** Deux horloges sont compatibles si elles sont comparables pour
l'inclusion. La lecture se réduit alors à un maintien ou à un échantillonnage pur.

La règle de lecture reste définie pour des horloges incomparables, mais on ne s'en
sert que dans `Sample` (section 4.3). Partout ailleurs, la traduction garantit des
horloges compatibles (section 4.1).

### 3.3 Loi de cohérence

Si $H \subseteq H'$, lire $x$ (d'horloge $H$) directement ou en passant par $H'$ donne
le même résultat :

$$x\lfloor \lfloor t \rfloor_{H'} \rfloor = x\lfloor t \rfloor$$

Passer par une horloge plus dense est toujours neutre. Passer par une horloge plus rare
perd de l'information : c'est une véritable opération.

## 4. Les signaux et leurs horloges

### 4.1 Calculs sans mémoire

Un calcul sans mémoire n'a pas d'horloge propre. Sa valeur ne peut changer qu'aux
instants où l'un de ses arguments change.

**[D] Discipline de chaîne.** Les horloges des arguments d'un calcul sans mémoire sont
toujours totalement ordonnées par l'inclusion. L'horloge du résultat est la plus dense,
donc celle de l'un des arguments. Le résultat est un signal sur cette horloge : il est
défini à ses tops, et se lit $0$ avant le premier.

Ce n'est pas une contrainte imposée à l'utilisateur. C'est un **invariant** que la
traduction établit (section 4.3) et que chaque transformation doit préserver. Sa
vérification est une obligation de certification : une violation est un défaut du
compilateur, pas une erreur du programme.

Un calcul dont tous les arguments sont des constantes est une constante.

### 4.2 Calculs avec mémoire

Un calcul avec mémoire impose son horloge, parce que son état avance au rythme d'une
horloge précise :

```faust
ramp = +(1) ~ _;
process = ramp, ondemand(ramp);   // deux rampes distinctes, deux états distincts
```

**[P]** Chaque constructeur à état reçoit son horloge en **argument**. L'horloge est
un terme ordinaire, hash-consé, dont la cadence $r$ est un sous-arbre visité par
toutes les transformations.

| Constructeur | Horloge |
|---|---|
| `Delay`$^c(x, d)$, `Prefix`$^c$, `FIR`$^c$, `IIR`$^c$, `IRM`$^c$ | argument $c$ |
| `WRTbl`$^c$ (écriture de table) | argument $c$ |
| `Sample`$^c(x)$ | argument $c$ |

Un calcul à mémoire d'horloge $c$ **lit ses arguments aux tops de $c$**, par la règle
de lecture. `Delay`$^c(x, d)$ est donc défini quelle que soit l'horloge de $x$ : il
retarde de $d$ tops de $c$ ce que $c$ voit de $x$.

Les groupes récursifs ne portent pas d'horloge. La composition `~` introduit un retard
d'un top de l'horloge lexicale, `Delay`$^c(\mathtt{Proj}(i,W), 1)$, et c'est ce retard
qui distingue les deux rampes de l'exemple.

Cela remplace les enveloppes `sigClocked`, qui obligeaient chaque règle de réécriture
à savoir les traverser. Cela corrige aussi un défaut de `FIR20` : l'environnement y
embarquait le signal $H$ brut, que les passes ne transformaient jamais.

### 4.3 L'échantillonnage

`Sample`$^c(x)$ est le calcul à mémoire le plus simple : le signal d'horloge $c$ qui
vaut $x\lfloor t \rfloor$ en chaque top $t$ de $c$. C'est le seul nœud qui change
l'horloge d'un signal. Il échantillonne quand $x$ est plus dense que $c$ et maintient
quand $x$ est plus rare ; pour une constante, il donne le signal d'horloge $c$ qui vaut
cette constante à chaque top.

Traduction des trois primitives, pour $P : n \to m$ et $c = p \triangleright r$,
l'indice de $[\![\cdot]\!]$ étant l'horloge lexicale courante :

$$[\![\mathtt{clocked}(P)]\!]_p(r, x_1..x_n) = (\mathtt{Sample}^p(\mathtt{Sample}^c(y_1)), \ldots)
\quad\text{où}\quad (y_1..y_m) = [\![P]\!]_c(\mathtt{Sample}^c(x_1), \ldots)$$

Toute source créée dans $P$ est traduite de même : un slider y devient
`Sample`$^c$`(slider)`, un signal extérieur capturé aussi.

**Chaîne d'un contexte.** Les horloges qu'un signal peut avoir dans le contexte
lexical $c$ forment une chaîne $\mathrm{Ch}(c)$ :

- $\mathrm{Ch}(\mathbf{S}) = \{\mathbf{B}, \mathbf{S}\}$ ;
- si $c = p \triangleright r$ est une subdivision : $\mathrm{Ch}(c) = \mathrm{Ch}(p) \cup \{c\}$ ;
- sinon : $\mathrm{Ch}(c) = \{c\}$.

**Entrée.** `Sample`$^c(x)$ s'efface quand l'horloge de $x$ est déjà dans
$\mathrm{Ch}(c)$. C'est le cas d'un slider au niveau principal, et de toute entrée
d'un `upsampling` : **[D]** l'entrée y est maintenue sur tous les sous-instants. Un
bourrage de zéros s'écrit dans $P$, avec un compteur. À l'entrée d'un `ondemand` ou
d'un `downsampling`, rien ne s'efface.

**[D] Sortie : passage par le parent.** `Sample`$^p$ en sortie ne s'efface jamais. La
sortie d'une région est un signal de l'horloge parente, quelle que soit la primitive :

- `ondemand`, `downsampling` : `Sample`$^p$ maintient la dernière valeur ;
- `upsampling` : `Sample`$^p$ décime en gardant le **premier** sous-échantillon.

Dans un contexte $c$, tout signal a donc une horloge de $\mathrm{Ch}(c)$, ou est une
constante : c'est la discipline de chaîne. Deux régions sœurs ne se lisent jamais
directement, et chaque région reste un bloc indépendant.

**Écart avec `FIR20`** : la sortie d'un `upsampling` y était le dernier
sous-échantillon. L'entrée y était pourtant visible de tous les sous-instants, ce qui
n'est cohérent avec aucun ordre total des instants.

### 4.4 Règles d'horloge

On note $\vdash s : H$ pour « $H$ est l'horloge de $s$ ».

$$\frac{}{\vdash k : \bot} \quad
\frac{}{\vdash \mathrm{SR} : \bot} \quad
\frac{}{\vdash \mathit{slider} : \mathbf{B}} \quad
\frac{}{\vdash \mathit{input}_i : \mathbf{S}}$$

$$\frac{\vdash s_i : H_i \quad \text{les } H_i \text{ forment une chaîne}}{\vdash \star(s_1,\ldots,s_n) : \max_i H_i}\ (\textit{op})
\qquad
\frac{}{\vdash \mathtt{Delay}^c(x,d) : c}\ (\textit{mem})
\qquad
\frac{\vdash \mathrm{def}_i(W) : H}{\vdash \mathtt{Proj}(i, W) : H}\ (\textit{proj})$$

$$\frac{r \in \mathbb{N} \text{ (prouvé par intervalle)}}
{p \triangleright r \ \text{bien formée}}\ (\textit{clk})$$

Remarques :

- L'horloge d'un signal est toujours **une** horloge, jamais un ensemble.
- La prémisse de (*op*) est l'invariant de la section 4.1. Les calculs à mémoire n'ont
  aucune prémisse : ils lisent leurs arguments par la règle de lecture.
- L'horloge d'un calcul à mémoire ne dépend pas de ses arguments. Comme toute
  référence récursive traverse un retard, le calcul des horloges se fait de bas en
  haut sans point fixe. Le point fixe de `clkEnvInference` disparaît.
- (*mem*) contient le fait que « c'est le retard qui rend un signal audio » :
  `slider'` est `Delay`$^{\mathbf{S}}$`(slider, 1)`.
- (*clk*) : la positivité et l'intégralité de $r$ sont des obligations de
  certification. `FIR20` se contentait d'un avertissement.
- L'inclusion n'est jamais à décider entre deux horloges quelconques : il suffit de
  connaître la position de chacune dans la chaîne du contexte.

### 4.5 Frontière d'observation

Un bargraph est un `Sample` vers $\mathbf{B}'$ (ou vers $\mathbf{B}$ : les deux
conviennent, la fin de bloc est seulement moins coûteuse à émettre). Le résultat dépend
de la taille des blocs. Un tel échantillonnage n'est admis que vers un puits et ne peut
pas réalimenter un calcul. C'est la frontière d'affichage actuelle, reformulée.

## 5. Lois algébriques

1. **Neutralité** : si l'horloge de $x$ est incluse dans $c$, `Sample`$^c(x)$ et $x$
   se lisent partout de la même façon. On ne remplace l'un par l'autre que si la
   discipline de chaîne est préservée (règles d'entrée et de sortie de 4.3).
2. **Absorption** : $\mathtt{Sample}^c(\mathtt{Sample}^{c'}(x)) = \mathtt{Sample}^c(x)$
   si $c \subseteq c'$. De même $\mathtt{Delay}^c(\mathtt{Sample}^c(x), d) = \mathtt{Delay}^c(x, d)$.
3. **Distribution** : $\mathtt{Sample}^c(\star(x_1,x_2)) = \star(\mathtt{Sample}^c(x_1), \mathtt{Sample}^c(x_2))$.
4. **Retards** : $\mathtt{Delay}^c(\mathtt{Delay}^c(x,a),b) = \mathtt{Delay}^c(x,a+b)$,
   seulement à horloge égale.
5. **Retard vu d'une sélection** : si $c \subseteq p$ et si $x$ est d'horloge $c$,
   alors $\mathtt{Sample}^c(\mathtt{Delay}^p(\mathtt{Sample}^p(x), 1)) = \mathtt{Delay}^c(x, 1)$.
   Un retard d'un top du parent, vu de la sélection, est un retard d'un top de la
   sélection. La loi ne vaut que pour un retard de $1$.
6. **Fusion** : `ondemand(P)(h) : ondemand(Q)(h)` $=$ `ondemand(P:Q)(h)`. Entre les
   deux, `Sample`$^c$`(Sample`$^p(y))$ se réduit à $y$ par la loi 2. Elle est fausse
   pour un `upsampling`, dont la sortie est décimée.
7. **Composition** : $(p \triangleright h_1) \triangleright h_0 = p \triangleright (h_1 \cdot h_0)$
   pour des cadences booléennes. C'est l'opérateur $h_0 \otimes h_1$ de la spec v5,
   plus simple ici parce que les instants sont absolus.
8. **Cas dégénérés** : $r = 1$ donne $p \triangleright r = p$, $r = 0$ donne l'horloge
   vide, dont tous les signaux se lisent $0$.

**Constantes.** `ondemand(1)` se traduit en `Sample`$^p$`(Sample`$^c(1))$ : $0$
jusqu'au premier top de $c$, puis $1$. C'est la sémantique de la spec v5. De même,
dans un `ondemand`, $x + 1$ est un signal d'horloge $c$, qui se lit $0$ avant le
premier top.

**Forme canonique. [P]** La loi 3 se lit dans les deux sens. On propose de faire
remonter `Sample` vers les consommateurs : il est alors absorbé par les calculs à
mémoire (loi 2), et il n'en reste qu'un par sortie.

## 6. Exemples déroulés

On note $c = \mathbf{S} \triangleright h$. Les codes sont ceux que les règles
désignent ; ils n'ont pas été produits par un compilateur.

### 6.1 Sample and hold

```faust
process = ondemand(_);        // entrées h, x
```

Traduction : `Sample`$^{\mathbf{S}}$`(Sample`$^c$`(Sample`$^c$`(x)))`. Par la loi 2
il reste `Sample`$^{\mathbf{S}}$`(Sample`$^c(x))$ : échantillonnage sur $c$, maintien
sur $\mathbf{S}$.

```c
if (h) { fSample0 = input1[i]; }
output0[i] = fSample0;
```

### 6.2 Bruit sous-échantillonné

```faust
process = ba.beat(100) : ondemand(no.noise);
```

Le générateur est le groupe $V$ de définition `Delay`$^c$`(Proj(0,V), 1) * 1103515245 + 12345`.
Le produit `Proj(0,V) * 4.65e-10` est d'horloge $c$ : la constante prend l'horloge de
l'autre argument. La sortie est `Sample`$^{\mathbf{S}}$ de ce produit.

```c
iVec0[0] = (iVec0[1] + 1) % 100;
if (iVec0[0] == 0) {
    iVec2[0] = 1103515245 * iVec2[1] + 12345;
    fSample0 = 4.656613e-10f * float(iVec2[0]);
    iVec2[1] = iVec2[0];
}
output0[i] = fSample0;
iVec0[1] = iVec0[0];
```

C'est le code des slides IFC-24.

### 6.3 Ondemand imbriqués

```faust
process = ondemand(ondemand(P));      // entrées h1, h0, x
```

$c_1 = \mathbf{S} \triangleright h_1$, puis $c_0 = c_1 \triangleright h_0$, $h_0$ étant
lu aux tops de $c_1$. Par la loi 7, $c_0 = \mathbf{S} \triangleright (h_1 \cdot h_0)$.
L'entrée `Sample`$^{c_0}$`(Sample`$^{c_1}$`(x))` se réduit à `Sample`$^{c_0}(x)$ par
la loi 2. Les deux `ondemand` n'en font qu'un, de garde `h1 && h0`.

### 6.4 Récursion à travers la frontière

```faust
process(h) = y letrec { 'y = ondemand(+(1))(h, y); };
```

Le groupe $U$, écrit sur $\mathbf{S}$, a pour définition
`Sample`$^{\mathbf{S}}(z)$ avec $z =$ `Sample`$^c$`(Delay`$^{\mathbf{S}}$`(Proj(0,U), 1)) + 1`,
d'horloge $c$. Le cycle contient un retard : il est causal. Par la loi 5, $z$ devient
`Delay`$^c(z, 1) + 1$ : l'état passe dans la région, et il ne reste aucun calcul par
échantillon.

```c
if (h) { iRec0[0] = iRec0[1] + 1; iRec0[1] = iRec0[0]; }
output0[i] = iRec0[0];
```

### 6.5 Upsampling et filtre

```faust
process = upsampling(+ ~ *(0.5));     // entrées N, x
```

$c = \mathbf{S} \triangleright N$, avec $\mathbf{S} \subseteq c$. `Sample`$^c(x)$
s'efface. Le filtre est le groupe $W$ de définition
`x + 0.5 * Delay`$^c$`(Proj(0,W), 1)`. La sortie est `Sample`$^{\mathbf{S}}$`(Proj(0,W))`.

```c
for (int j = 0; j < N; j++) {
    fRec0[0] = input1[i] + 0.5f * fRec0[1];
    if (j == 0) { fSample0 = fRec0[0]; }
    fRec0[1] = fRec0[0];
}
output0[i] = fSample0;
```

### 6.6 Slider dans un ondemand

```faust
process = ondemand(*(hslider("gain", 1, 0, 1, 0.01)));
```

Dans la région : `Sample`$^c(x)$ `* Sample`$^c$`(gain)`, d'horloge $c$. Le gain est
figé entre deux demandes, comme l'exige la propriété « la sortie reste constante
jusqu'à la prochaine demande ».

## 7. Horloge de définition, de demande, d'exécution

- **Définition** : l'horloge de la section 4.4, calculée de bas en haut.
- **Demande** : les horloges des consommateurs, propagée de haut en bas.
- **Exécution** : l'horloge où le code est émis.

Pour un nœud à état, l'exécution est la définition, sans choix possible : un écho
inaudible vieillit quand même. C'est la règle `isConditionBoundary` de
`certification-4`, qui devient une conséquence et non plus une liste de cas.

Pour un nœud sans état, la loi de cohérence laisse le choix : toute horloge qui
contient les instants demandés convient. Il en va de même d'un `Sample` qui maintient
(sortie d'un `ondemand`) : il ne coûte qu'une variable. Le choix est une optimisation :

- vers une horloge plus rare : appel par nécessité (ne pas calculer l'entrée d'un
  `ondemand` quand il ne tourne pas) ;
- vers une horloge moins dense : sortie des invariants de boucle (sliders hors de la
  boucle d'échantillons, entrée d'un `upsampling`).

Les gardes de `-lazyselect` sont alors des horloges booléennes anonymes sur du code
sans état, et `enable`/`control` (annoncés comme remplacés par `ondemand` dans
`compile_scal.hh`) n'ont plus de raison d'être.

## 8. Causalité, mémoire, certification

- **Causalité.** Une région d'horloge est un nœud du graphe de son parent. Toute
  boucle de dépendances doit contenir un retard. $r$ ne peut pas dépendre
  instantanément d'un signal de sa propre horloge.
- **Mémoire.** L'état appartient au signal, pas à l'horloge. Chaque horloge a son
  propre index de temps (un IOTA par horloge, comme dans `FIR20`). Lire un signal plus
  rare coûte une variable qui garde la dernière valeur (le `PermVar` de `FIR20`).
- **Horizon.** L'analyse d'intervalles affine en temps de `sighorizon` compte en
  échantillons. Sur $p \triangleright r$, le temps local est borné par $\sup(r)$ fois
  le temps parent. Une cadence de subdivision doit donc être bornée.
- **Faux refus.** `tests/TESTING.md` signale deux défauts ouverts de l'analyse
  d'intervalles (`-ftz`, `int()` d'une valeur non bornée puis masquée). Une cadence
  écrite sous ces formes serait refusée par (*clk*).
- **Invariant de la branche.** Une seule référence sémantique, indépendante du
  backend, de la vectorisation et de l'ordonnancement. Les sections 2 et 3 la
  fournissent.
- **Vectorisation.** Une horloge de cadence constante est *périodique* : sa région peut
  devenir une boucle sœur de longueur $N \cdot \mathit{count}$ ou $\mathit{count}/N$.
  Une horloge dépendante des données reste scalaire dans sa région. `FIR20` refusait
  `-vec` en bloc.

## 9. Ce qui se réutilise, ce qui change

**De `certification-4`**

| Existant | Rôle dans le calcul d'horloges |
|---|---|
| `SignalAlgebra<V>` et `FixPointIterator` | `ClockAlgebra` pour l'horloge de définition. « Rien n'est défini par défaut » impose une règle par constructeur |
| `tlib/descend.hh`, régime B | horloge de demande. Le commentaire prévoit déjà cet usage |
| `VariabilityAlgebra`, `ComputabilityAlgebra` | conservées. L'horloge est calculée à côté, avec un test de concordance (section 10) |
| `conditionAnnotation`, `Statement(cond)`, `ControlInst` | émission des régions à cadence booléenne |
| frontière d'affichage, `controlCS` | instance de `Sample` vers $\mathbf{B}'$ |
| zones de `Klass` (init, bloc, boucle) | les constantes, puis les horloges $\mathbf{B}$ et $\mathbf{S}$ |
| `GroupPlan` (arbre de groupes) | hôte naturel d'un groupe « région d'horloge » |
| boucles internes de `-fam` | modèle d'émission pour la boucle d'un `upsampling` |
| IOTA global | à rendre propre à chaque horloge |
| portes de test (canonicité, déterminisme, mémoire) | à étendre aux programmes à horloges |

**De `FIR20`**

| Élément | Devenir |
|---|---|
| lexer, parser, boîtes, typage $(u+1) \to v$, schémas | repris tels quels |
| `propagate(clockenv, …)` et adaptation de `SR` | repris, l'environnement devient le terme d'horloge |
| formes `if` / `for` / compteur | reprises à l'émission |
| `sigClocked`, `sigDoubleClocked` | remplacés par l'argument d'horloge des constructeurs à état |
| `sigOD`/`sigUS`/`sigDS`, `sigSeq` | supprimés : la région se déduit de l'horloge d'exécution |
| `sigTempVar`, `sigPermVar` | un seul nœud, `Sample`$^c$ |
| `sigZeroPad` | supprimé : maintien en entrée, bourrage écrit par l'utilisateur |
| `clkEnvInference` (point fixe, erreurs d'incomparabilité) | calcul direct ; l'incomparabilité devient une vérification d'invariant |
| identité nominale des environnements | identité structurelle |
| sortie d'`upsampling` au dernier sous-échantillon | premier sous-échantillon (convention « début ») |
| erreurs sans localisation, refus de `-vec` | à corriger |

## 10. Concordance avec la variabilité

**[D]** L'horloge est calculée à côté de la variabilité, sans la remplacer. Un test
vérifie que les deux concordent.

### 10.1 La projection

$$\pi(\bot) = \mathtt{kKonst} \qquad \pi(\mathbf{B}) = \mathtt{kBlock} \qquad
\pi(\mathbf{S}) = \mathtt{kSamp} \qquad \pi(p \triangleright r) = \mathtt{kSamp}$$

**Test de concordance** : pour tout nœud $s$ de tout programme,
$\pi(H(s)) = \mathrm{variabilité}(s)$, aux écarts répertoriés près.

### 10.2 Règle par règle

Comparaison avec `VariabilityAlgebra` (`signals/sigattributes.cpp`), lue sur
`certification-4` :

| Constructeur | Variabilité actuelle | Horloge | Concordance |
|---|---|---|---|
| nombres, `ForeignConst`, `Highest`, `Lowest` | `kKonst` | $\bot$ | oui |
| widgets, `SoundFile`, `ForeignVar` | `kBlock` | $\mathbf{B}$ | oui |
| `Input`, `Output` | `kSamp` | $\mathbf{S}$ | oui |
| opérations, `Select2`, `RDTbl`, `Sum`, `Prod`, `Bpf` | jointure des arguments | maximum de la chaîne | oui |
| `Mem`, `Delay`, `Prefix`, `IIR`, `IRM` | `kSamp` | argument $c$ | oui |
| `Waveform`, `SoundFileBuffer`, fonction étrangère sans argument | `kSamp` | $\mathbf{S}$ (source) | oui |
| `Table` (lecture seule), `Gen` | `kKonst` | $\bot$ (temps différé) | oui |
| bargraph | `s \| kBlock` | $\max(H(s), \mathbf{B})$ | oui |
| `FIR` à un seul coefficient | celle de l'entrée | à traiter comme une opération | à aligner |
| `WRTbl` | `kKonst \| wi \| ws` | argument $c$ | **écart** |
| projection d'un groupe récursif | jointure de tout le groupe | horloge de sa propre définition | **à vérifier** |

Deux points à examiner :

- **`WRTbl`.** La variabilité d'une table écrite est celle de son index et de son
  signal d'écriture : une table écrite au rythme des blocs est `kBlock`. C'est
  légitime, parce que réécrire la même valeur au même index est sans effet. La règle
  (*mem*) lui donnerait $\mathbf{S}$. Il faut soit accepter l'écart, soit donner à
  l'écriture de table l'horloge de ses arguments.
- **Groupes récursifs.** La variabilité actuelle donne à toutes les projections d'un
  groupe la même valeur. L'horloge est calculée par projection. Les deux coïncident si
  chaque définition traverse un retard, ce qui devrait être le cas après
  `normalizeRecGroups` ; ce n'est pas vérifié.

### 10.3 Étape 0 de l'implémentation

Avant d'ajouter la moindre primitive, on peut écrire `ClockAlgebra` restreinte aux
horloges naturelles ($\bot$, $\mathbf{B}$, $\mathbf{S}$) et passer le test de
concordance sur toute la suite de tests existante. Aucun programme actuel n'a
d'horloge dérivée : le test valide donc les règles de la section 4.4 sur l'existant,
sans changer le code généré.

## 11. Questions ouvertes

- **[Q1]** Sens canonique de la loi de distribution (section 5) : remontée de `Sample`
  vers les consommateurs, comme proposé ?
- **[Q2]** Sorties qui *collectent* (`vectorize`/`serialize`, trames FFT,
  `interleave`) : le générateur de table en est déjà une. À prévoir dans les types dès
  maintenant ?
- **[Q3]** `switch(C0..Ck)` : horloges de cadences complémentaires. Faut-il une notion
  d'horloges *exclusives* pour partager l'état ou le code ?
- **[Q4]** Cadence quelconque ($r$ tantôt nul, tantôt supérieur à 1) : à conserver, ou
  à restreindre à la sélection et à la subdivision pures ?
- **[Q5]** Cadence définie sur $\mathbf{B}$ (ondemand piloté par un slider) : la région
  doit-elle sortir de la boucle d'échantillons ?
