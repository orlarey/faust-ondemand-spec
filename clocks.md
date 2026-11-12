# Un calcul d'horloges pour Faust

**[Brouillon v2 — document de travail, 12 novembre 2026]**

Objet : poser la théorie des horloges qui servira de base à la réimplémentation de
`ondemand`, `upsampling` et `downsampling` sur `master-dev-certification-4`.
Ce document ne spécifie que la logique des horloges ; il ne décrit pas encore
l'implémentation. Les propositions notées **[P]** sont des choix de conception
soumis à discussion, les points notés **[Q]** sont des questions ouvertes, les points
notés **[D]** sont décidés.

Changements depuis la v1 : identité structurelle, passage par le parent pour les
subdivisions et maintien en entrée d'`upsampling` sont décidés ; les calculs à mémoire
échantillonnent implicitement leurs arguments, ce qui supprime toutes les contraintes
d'horloge ; les groupes récursifs ne portent plus d'horloge ; l'instant initial est
l'échantillon 0 ; ajout d'exemples déroulés (section 6).

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
| $\mathbf{I}$ | l'instant initial, qui est l'échantillon $0$ |

On a $\mathbf{I} \subset \mathbf{B} \subset \mathbf{S}$ et $\mathbf{B}' \subset \mathbf{S}$.
Les constantes sont des signaux sur $\mathbf{I}$, les sliders des signaux sur
$\mathbf{B}$, les entrées audio des signaux sur $\mathbf{S}$. On sait que
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
Les calculs d'initialisation s'exécutent eux aussi en temps différé, mais leur
résultat est un signal d'horloge $\mathbf{I}$.

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
l'inclusion. Ce n'est pas une condition de validité : `ondemand(P)(h1) : ondemand(Q)(h2)`
met en jeu deux horloges incomparables et reste un programme légitime. La
compatibilité dit quand la lecture se réduit à un maintien ou à un échantillonnage pur.

### 3.3 Loi de cohérence

Si $H \subseteq H'$, lire $x$ (d'horloge $H$) directement ou en passant par $H'$ donne
le même résultat :

$$x\lfloor \lfloor t \rfloor_{H'} \rfloor = x\lfloor t \rfloor$$

Passer par une horloge plus dense est toujours neutre. Passer par une horloge plus rare
perd de l'information : c'est une véritable opération.

## 4. Les signaux et leurs horloges

### 4.1 Calculs sans mémoire

Un calcul sans mémoire n'a pas d'horloge propre. Sa valeur ne peut changer qu'aux
instants où l'un de ses arguments change. Son horloge est donc **l'union** des horloges
de ses arguments.

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
vaut $x\lfloor t \rfloor$ en chaque top $t$ de $c$. C'est la seule traversée
explicite ; le maintien n'a pas besoin de nœud.

Traduction des trois primitives, pour $P : n \to m$ et $c = p \triangleright r$,
l'indice de $[\![\cdot]\!]$ étant l'horloge lexicale courante :

$$[\![\mathtt{clocked}(P)]\!]_p(r, x_1..x_n) = (\mathtt{Sample}^p(\mathtt{Sample}^c(y_1)), \ldots)
\quad\text{où}\quad (y_1..y_m) = [\![P]\!]_c(\mathtt{Sample}^c(x_1), \ldots)$$

La traduction est uniforme ; ce sont les lois de la section 5 qui font la différence
entre les primitives :

- **`ondemand`, `downsampling`** ($c \subseteq p$) : `Sample`$^p$ en sortie s'efface.
  Il reste `Sample`$^c$ : la sortie est constante entre deux demandes.
- **`upsampling`** ($p \subseteq c$) : **[D]** `Sample`$^c$ en entrée s'efface, l'entrée
  est maintenue sur tous les sous-instants. `Sample`$^p$ en sortie décime en gardant le
  **premier** sous-échantillon. Un bourrage de zéros s'écrit dans $P$, avec un compteur.

**[D] Passage par le parent.** La sortie d'une subdivision est toujours échantillonnée
sur son parent, et aucune loi n'efface cet échantillonnage. Un signal d'une subdivision
n'est donc jamais lu depuis une autre subdivision non emboîtée ; chaque région reste
une boucle interne indépendante.

**Écart avec `FIR20`** : la sortie d'un `upsampling` y était le dernier
sous-échantillon. L'entrée y était pourtant visible de tous les sous-instants, ce qui
n'est cohérent avec aucun ordre total des instants.

### 4.4 Règles d'horloge

On note $\vdash s : H$ pour « $H$ est l'horloge de $s$ ».

$$\frac{}{\vdash k : \mathbf{I}} \quad
\frac{}{\vdash \mathrm{SR} : \mathbf{I}} \quad
\frac{}{\vdash \mathit{slider} : \mathbf{B}} \quad
\frac{}{\vdash \mathit{input}_i : \mathbf{S}}$$

$$\frac{\vdash s_i : H_i}{\vdash \star(s_1,\ldots,s_n) : \bigcup_i H_i}\ (\textit{op})
\qquad
\frac{}{\vdash \mathtt{Delay}^c(x,d) : c}\ (\textit{mem})
\qquad
\frac{\vdash \mathrm{def}_i(W) : H}{\vdash \mathtt{Proj}(i, W) : H}\ (\textit{proj})$$

$$\frac{r \in \mathbb{N} \text{ (prouvé par intervalle)}}
{p \triangleright r \ \text{bien formée}}\ (\textit{clk})$$

Remarques :

- Il n'y a **aucune contrainte entre horloges** : toute combinaison est définie par la
  règle de lecture. Les seules obligations sont (*clk*) et la causalité.
- L'horloge d'un calcul à mémoire ne dépend pas de ses arguments. Comme toute
  référence récursive traverse un retard, le calcul des horloges se fait de bas en
  haut sans point fixe. Le point fixe de `clkEnvInference` disparaît.
- (*mem*) contient le fait que « c'est le retard qui rend un signal audio » :
  `slider'` est `Delay`$^{\mathbf{S}}$`(slider, 1)`.
- (*clk*) : la positivité et l'intégralité de $r$ sont des obligations de
  certification. `FIR20` se contentait d'un avertissement.
- L'inclusion, utile aux lois de la section 5, est décidée par des conditions
  suffisantes syntaxiques : sélection, subdivision, transitivité.

### 4.5 Frontière d'observation

Un bargraph est un `Sample` vers $\mathbf{B}'$ (ou vers $\mathbf{B}$ : les deux
conviennent, la fin de bloc est seulement moins coûteuse à émettre). Le résultat dépend
de la taille des blocs. Un tel échantillonnage n'est admis que vers un puits et ne peut
pas réalimenter un calcul. C'est la frontière d'affichage actuelle, reformulée.

## 5. Lois algébriques

1. **Effacement** : $\mathtt{Sample}^c(x) = x$ si l'horloge de $x$ est incluse dans $c$.
2. **Absorption** : $\mathtt{Sample}^c(\mathtt{Sample}^{c'}(x)) = \mathtt{Sample}^c(x)$
   si $c \subseteq c'$. De même $\mathtt{Delay}^c(\mathtt{Sample}^c(x), d) = \mathtt{Delay}^c(x, d)$.
3. **Distribution** : $\mathtt{Sample}^c(\star(x_1,x_2)) = \star(\mathtt{Sample}^c(x_1), \mathtt{Sample}^c(x_2))$.
4. **Retards** : $\mathtt{Delay}^c(\mathtt{Delay}^c(x,a),b) = \mathtt{Delay}^c(x,a+b)$,
   seulement à horloge égale.
5. **Retard vu d'une sélection** : si $c \subseteq p$ et si l'horloge de $x$ est
   incluse dans $c$, alors $\mathtt{Sample}^c(\mathtt{Delay}^p(x, 1)) = \mathtt{Delay}^c(x, 1)$.
   Un retard d'un top du parent, vu de la sélection, est un retard d'un top de la
   sélection. La loi ne vaut que pour un retard de $1$.
6. **Fusion** : `ondemand(P)(h) : ondemand(Q)(h)` $=$ `ondemand(P:Q)(h)`. Elle découle
   des lois 1 et 2 et de l'égalité structurelle. Elle est fausse pour un `upsampling`,
   dont la sortie est décimée.
7. **Composition** : $(p \triangleright h_1) \triangleright h_0 = p \triangleright (h_1 \cdot h_0)$
   pour des cadences booléennes. C'est l'opérateur $h_0 \otimes h_1$ de la spec v5,
   plus simple ici parce que les instants sont absolus.
8. **Cas dégénérés** : $r = 1$ donne $p \triangleright r = p$, $r = 0$ donne l'horloge
   vide, dont tous les signaux se lisent $0$.

**Constantes.** $\mathbf{I} \subseteq c$ si et seulement si $c$ a un top à l'instant
$0$. Sinon `Sample`$^c(1)$ ne s'efface pas : il vaut $0$ jusqu'au premier top de $c$,
puis $1$. C'est la sémantique de la spec v5 pour `ondemand(1)`, obtenue sans cas
particulier. Au niveau principal, `Sample`$^{\mathbf{S}}(k) = k$.

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

Traduction : `Sample`$^{\mathbf{S}}$`(Sample`$^c$`(Sample`$^c$`(x)))`. Par les lois 2
et 1 il reste `Sample`$^c(x)$, d'horloge $c$, lu sur $\mathbf{S}$ par maintien.

```c
if (h) { fSample0 = input1[i]; }
output0[i] = fSample0;
```

### 6.2 Bruit sous-échantillonné

```faust
process = ba.beat(100) : ondemand(no.noise);
```

Le générateur est le groupe $V$ de définition `Delay`$^c$`(Proj(0,V), 1) * 1103515245 + 12345`.
La sortie est `Sample`$^c$`(Proj(0,V) * 4.65e-10)`. L'horloge de l'argument est
$c \cup \mathbf{I}$, à cause de la constante ; `Sample`$^c$ ne s'efface donc pas.

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
`Sample`$^c$`(Delay`$^{\mathbf{S}}$`(Proj(0,U), 1) + 1)`. Le cycle contient un retard :
il est causal. L'horloge de `Proj(0,U)` est $c$. Par les lois 3 et 5, la définition
devient `Delay`$^c$`(Proj(0,U), 1) + Sample`$^c$`(1)` : l'état passe dans la région, et
il ne reste aucun calcul par échantillon.

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

Sortie : `Sample`$^c$`(x * gain)`. Le gain est figé entre deux demandes, comme
l'exige la propriété « la sortie reste constante jusqu'à la prochaine demande ».

## 7. Horloge de définition, de demande, d'exécution

- **Définition** : l'horloge de la section 4.4, calculée de bas en haut.
- **Demande** : les horloges des consommateurs, propagée de haut en bas.
- **Exécution** : l'horloge où le code est émis.

Pour un nœud à état, l'exécution est la définition, sans choix possible : un écho
inaudible vieillit quand même. C'est la règle `isConditionBoundary` de
`certification-4`, qui devient une conséquence et non plus une liste de cas.

Pour un nœud sans état, la loi de cohérence laisse le choix : toute horloge qui
contient les instants demandés convient. Le choix est une optimisation :

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
| `VariabilityAlgebra`, `ComputabilityAlgebra` | deviennent des projections de l'horloge. À conserver d'abord en parallèle, avec un test de cohérence |
| `conditionAnnotation`, `Statement(cond)`, `ControlInst` | émission des régions à cadence booléenne |
| frontière d'affichage, `controlCS` | instance de `Sample` vers $\mathbf{B}'$ |
| zones de `Klass` (init, bloc, boucle) | les horloges $\mathbf{I}$, $\mathbf{B}$, $\mathbf{S}$ |
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
| `clkEnvInference` (point fixe, erreurs d'incomparabilité) | supprimé : calcul direct, aucune contrainte |
| identité nominale des environnements | identité structurelle |
| sortie d'`upsampling` au dernier sous-échantillon | premier sous-échantillon (convention « début ») |
| erreurs sans localisation, refus de `-vec` | à corriger |

## 10. Questions ouvertes

- **[Q1]** Les horloges $\mathbf{I}$, $\mathbf{B}$, $\mathbf{S}$ remplacent-elles la
  variabilité à terme, ou restent-elles une vue au-dessus de l'existant ?
- **[Q2]** Sens canonique de la loi de distribution (section 5) : remontée de `Sample`
  vers les consommateurs, comme proposé ?
- **[Q3]** L'union d'horloges comme attribut : ensemble fini d'horloges, réduit par
  les inclusions connues. Faut-il la représenter exactement, ou se contenter d'un
  majorant (la plus petite horloge nommée qui la contient) ?
- **[Q4]** Sorties qui *collectent* (`vectorize`/`serialize`, trames FFT,
  `interleave`) : le générateur de table en est déjà une. À prévoir dans les types dès
  maintenant ?
- **[Q5]** `switch(C0..Ck)` : horloges de cadences complémentaires. Faut-il une notion
  d'horloges *exclusives* pour partager l'état ou le code ?
- **[Q6]** Cadence quelconque ($r$ tantôt nul, tantôt supérieur à 1) : à conserver, ou
  à restreindre à la sélection et à la subdivision pures ?
- **[Q7]** Cadence définie sur $\mathbf{B}$ (ondemand piloté par un slider) : la région
  doit-elle sortir de la boucle d'échantillons ?
