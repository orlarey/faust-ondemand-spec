# _On-demand_ computations in FAUST

## Introduction

There is a request for using Faust in a more _composition-oriented_ way. This can be done by introducing _on-demand_ computations. The challenge is to do that while keeping the simple and well defined semantics of Faust.

For that purpose we introduce a new $\mathtt{ondemand}(P)\rightarrow P'$ primitive that operates on signal processors (not on signals). Informally, the resulting signal processor $P'$ is like $P$, but with an additional input for a clock signal and an _on-demand_ semantics. As we will see, this _on-demand_ semantics can be expressed using the regular Faust semantics but applied to downsampled signals.

## Type of $\mathtt{ondemand}(P)$

If $P$ has $n$ inputs and $m$ outputs, then $\mathtt{ondemand}(P)$ has $n+1$ inputs and $m$ outputs. The additional input is a clock signal.
$$
\frac{P:n\rightarrow m}{\mathtt{ondemand}(P):1+n\rightarrow m}
$$


## The clock signals $h$

The additional input of $\mathtt{ondemand}(P)$ is a clock signal $h$ that indicates by a $1$ when there is a computation demand, and by $0$ otherwise. In other words $h(t)=1$ means that there is a computation demand at time $t$.

Form signal $h$ we can derive a signal $\bar{h}$ that indicates the time of each demand. For example if $h=1,0,0,1,0,0,0,1,0\ldots$ then $\bar{h}=0,3,7,\ldots$ indicating that the first demand is at time $0$, the second one at time $3$, the third one at time $7$, etc.

We derive also another signal $h^+$ that _counts_ the number of demandes: $h^+(t) = h^+(t-1)+h(t)$ (with $h^+(t<0)=0$). For the same $h=1,0,0,1,0,0,0,1,0\ldots$ we have $h^+=1,1,1,2,2,2,2,3,3,\ldots$

## Downsampling and Upsampling

Now that we have defined the clocks signals $h$ and $\bar{h}$, we can introduce the _downsampling_ and _upsampling_  operations needed to express the _on-demand_ semantics. 

### Downsampling

The downsamplig operation is notated $\downarrow_{h}$. For a signal $x$, the downsampled signal $\downarrow_{h}(x)$ is defined as:
$$
\downarrow_{h}(x) = \lambda t.x(\bar{h}(t))
$$
For example if $x=0.0, -0.1, -0.2, -0.3, -0.4, -0.5, -0.6, -0.7,\ldots$ and  $\bar{h}=0,3,7,\ldots$, then $\downarrow_{h}(x) = 0.0,-0.3,-0.7,\ldots$ 

### Upsampling

The reverse _upsampling_ operation, notated $\uparrow_{h}$, expands the input signal by repeating the missing values. 
$$
\uparrow_{h}(x) = \lambda t.x(h^+(t)-1)
$$

For example if $ x = 0.0,-0.3,-0.7,\ldots$  and $h^+=1,1,1,2,2,2,2,3,3,\ldots$ then $\uparrow_{h}(x) = 0.0,0.0,0.0,-0.3,-0.3,-0.3,-0.3,-0.7,\ldots$ 

> _NOTE_: please note that $\uparrow_{h}:\downarrow_{h}$ is the identity function, but that is not true for $\downarrow_{h}:\uparrow_{h}$.

# Semantics of $\mathtt{ondemand}(P)$

Let's $P:n\rightarrow m$ be a signal processor with $n$ inputs and $m$ outputs and with semantics $[\![P]\!]$.  The semantics of $\mathtt{ondemand}(P)$, notated $[\![\mathtt{ondemand}(P)]\!]$ is defined by the following rule:
$$
\frac{[\![P]\!](\downarrow_h(x_1),\ldots,\downarrow_h(x_n))=(y_1,\ldots,y_m)}
{[\![\mathtt{ondemand}(P)]\!](h, x_1,\ldots,x_n)= (\uparrow_h(y_1),\ldots,\uparrow_h(y_m))}
$$

As we can see, $[\![\mathtt{ondemand}(P)]\!]$ is $[\![P]\!]$ applied to downsampled versions of the input signals. The downsampling depends on the demand clock $h$. The resulting signals of $[\![\mathtt{ondemand}(P)]\!]$ are the upsampled versions of the resulting signals of $[\![P]\!]$.