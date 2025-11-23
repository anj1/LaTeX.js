'use strict'

export class Amsmath

    # Core amsmath environments that should be treated as display math blocks
    # and passed directly to KaTeX.
    mathEnvs = <[
        equation equation*
        align align*
        alignat alignat*
        gather gather*
        flalign flalign*
        multline multline*
        split
    ]>

    args = @args = {}

    # CTOR
    (generator, options) ->
        @g = generator

        # Register environments so the parser treats them as math blocks
        for env in mathEnvs
            @g.addMathEnv env

        # Pre-register basic amsmath commands for KaTeX if they aren't built-in 
        # (KaTeX supports most, but we can add overrides here if needed)
        
        # Setup counters usually provided by amsmath
        # 'equation' is standard, but 'subequation' might be needed
        @g.newCounter "parentequation" unless @g.hasCounter "parentequation"


    # 3.11.2 Cross references to equation numbers
    # \eqref{label} -> (\ref{label})
    args.\eqref = <[ H g ]>
    \eqref : (label) ->
        [
            @g.createText "("
            @g.ref label.textContent
            @g.createText ")"
        ]


    # 3.11.1 Numbering hierarchy
    # \numberwithin{counter}{section}
    args.\numberwithin = <[ P i i ]>
    \numberwithin : (counter, section) !->
        # Resets 'counter' when 'section' is stepped
        @g.addToReset counter, section

        # Redefine \thecounter to include the section: \thesection.\arabic{counter}
        # We need to construct this definition dynamically
        
        # This implementation mimics: \renewcommand{\theequation}{\thesection.\arabic{equation}}
        @g._macros["the" + counter] = ~>
            # Result is [Node]
            res = []
            
            # Get \thesection (or whatever parent)
            if @g.hasMacro "the" + section
                res = res ++ @g.macro "the" + section

            res.push @g.createText "."
            res.push @g.arabic @g.counter counter
            
            res


    # 5.1 Defining new operator names
    # \DeclareMathOperator{\name}{text}
    # \DeclareMathOperator*{\name}{text} (limits)
    args.\DeclareMathOperator = <[ P s m g ]>
    \DeclareMathOperator : (star, cmd, text) !->
        # cmd comes in as a string, e.g., "myop" (without backslash if parsed via 'm' arg type usually, 
        # but macro_group in parser returns the id string)
        
        opName = "\\" + cmd
        defText = text.textContent
        
        # Register for KaTeX
        # \operatorname{text} or \operatorname*{text}
        katexDef = "\\operatorname" + (if star then "*" else "") + "{" + defText + "}"
        @g.addMathMacro opName, katexDef

        # Also define it for text mode in latex.js, just in case
        @g._macros[cmd] = ~>
            # Check if we are inside a math environment? 
            # Usually \DeclareMathOperator is used inside math. 
            # If used in text, we wrap in inline math.
            @g.create @g.inline, [
                @g.createText defText
            ], "mathrm" 


    # 4.2 Math spacing commands
    # These are usually handled inside KaTeX, but if they appear in text mode
    # or need specific handling, we define them.
    # amsmath adds: \thinspace, \medspace, \thickspace, \negthinspace, etc.
    # latex.lts.ls already has some.
    
    args.\mspace = <[ H l ]>
    \mspace : (len) ->
        [ @g.createHSpace len ]


    # 6 The \text command
    # \text{...}
    # KaTeX handles \text inside math. 
    # If encountered in H-mode in latex.js (outside math env), it's just a wrapper.
    args.\text = <[ H g ]>
    \text : (content) ->
        # Just return the content fragment
        [ content ]


    # 4.14 Delimiters
    # \lvert, \rvert, \lVert, \rVert
    # Defined for text mode usage (rare) or ensured for Math.
    
    args.\lvert = <[ H ]>
    \lvert : -> [ "|" ]

    args.\rvert = <[ H ]>
    \rvert : -> [ "|" ]

    args.\lVert = <[ H ]>
    \lVert : -> [ "∥" ]

    args.\rVert = <[ H ]>
    \rVert : -> [ "∥" ]


    # 3.11.3 Subordinate numbering sequences
    # \begin{subequations} ... \end{subequations}
    args.\subequations = <[ V b ]>
    \subequations : (content) ->
        # Logic:
        # 1. Save current equation counter
        # 2. Change equation counter printing to 1.1a
        # 3. Process content
        # 4. Restore
        
        # Note: Implementing full scoping reset in this architecture is tricky 
        # because the 'content' is already parsed when passed to this macro (arg type 'b' block).
        # However, for 'V' macros, the content is parsed *after*? 
        # No, 'b' argument consumes the environment body.
        
        # Since 'equation' handling is often delegated to KaTeX in this specific setup,
        # handling subequations for *HTML generation* purely in latex.js is limited 
        # unless we wrap the whole block.
        
        # Minimal implementation: treat as a block.
        # Ideally, we would manipulate the 'equation' counter here.
        
        @g.stepCounter "parentequation"
        @g.setCounter "parentequation", @g.counter "equation"
        @g.setCounter "equation", 0
        
        # Save old \theequation
        oldTheEquation = @g._macros.theequation
        
        # Redefine \theequation to \theparentequation\alph{equation}
        @g._macros.theequation = ~>
             p = if @g.hasMacro "theparentequation" then @g.macro "theparentequation" else @g.arabic @g.counter "parentequation"
             p ++ @g.alph "equation"

        res = content
        
        # Restore (Reset logic is simplistic here, scope handling handles stack)
        @g._macros.theequation = oldTheEquation
        @g.setCounter "equation", @g.counter "parentequation"
        
        [ res ]


    # 4.11 Fractions (wrappers if used in text mode, though unlikely)
    args.\dfrac = <[ H g g ]>
    \dfrac : (num, den) ->
        # Force display style fraction in math, but in text mode?
        # Just return standard text fraction or error? 
        # Usually errors in LaTeX if not in math mode.
        @g.error "\\dfrac used in text mode"
    
    args.\tfrac = <[ H g g ]>
    \tfrac : (num, den) ->
        @g.error "\\tfrac used in text mode"
        
    args.\binom = <[ H g g ]>
    \binom : (n, k) ->
        @g.error "\\binom used in text mode"


    # 4.1 Matrices
    # pmatrix, etc are handled by adding them to mathEnvs, 
    # or they are used inside standard \[ ... \] blocks which parse as math primitives.
    # We do not need explicit definitions here unless we want to support them in text mode (which is invalid).
    
    # However, 'smallmatrix' is often used inline.
    # \begin{smallmatrix} ... \end{smallmatrix}
    # If the parser encounters this inside $...$, it works via KaTeX.
    # If encountered at top level, we might want to support it.
    
    # The mathEnvs list handles top-level display blocks. 
    # smallmatrix is usually inline. 
    # Users should write $\begin{smallmatrix}...\end{smallmatrix}$.