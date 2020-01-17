
# const csskey = AssetRegistry.register(joinpath(dirname(pathof(DynamicGridsInteract)), "../assets/web.css"))

# TODO update themes
# Custom css theme
# struct WebTheme <: WidgetTheme end

# libraries(::WebTheme) = vcat(libraries(InteractBulma.BulmaTheme()), [csskey])


"Interact outputs including InteractOuput, ElectronOutput and ServerOutput"
abstract type AbstractInteractOutput{T} <: ImageOutput{T} end


"""
    InteractOutput(init, ruleset; fps=25, showfps=fps, store=false,
                   processor=ColorProcessor(), extrainit=Dict())

An `Output` for Atom/Juno and Jupyter notebooks,
and the back-end for [`ElectronOutput`](@ref) and [`ServerOutput`](@ref).


### Arguments:
- `init`: an Array or NamedTuple of arrays.
- `ruleset`: the ruleset to run in the interface simulations.

### Keyword Arguments:
- `fps::Real`: frames per second
- `showfps::Real`: maximum displayed frames per second
- `store::Bool`: store the simulation frames to be used afterwards
- `processor::FrameProcessor
- `minval::Number`: Minimum value to display in the simulation
- `maxval::Number`: Maximum value to display in the simulation

"""
@Image @Graphic @Output mutable struct InteractOutput{Pa,IM,TI,EI} <: AbstractInteractOutput{T}
    # Field       | Default: @Output macro chains @default_kw
    page::Pa      | nothing
    image_obs::IM | nothing
    t_obs::TI     | nothing
    extrainit::EI | nothing
end

InteractOutput(frame, ruleset; kwargs...) = InteractOutput([frame], ruleset; kwargs...)
InteractOutput(frames::AbstractVector, ruleset; tspan=(1, 1000),
               extrainit=Dict(), throttle=0.1, kwargs...) = begin

    # settheme!(theme)
    extrainit[:init] = first(frames)

    init = deepcopy(frames[1])

    # Standard output and controls
    image_obs = Observable{Any}(dom"div"())

    timedisplay = Observable{Any}(dom"div"("0"))
    t_obs = Observable{Int}(1)
    map!(timedisplay, t_obs) do t
        dom"div"(string(t))
    end

    o = InteractOutput(; frames=frames, page=vbox(), image_obs=image_obs,
                       t_obs=t_obs, extrainit=extrainit, kwargs...)

    # timespan_obs = Observable{Int}(DynamicGrids.stoptime(ui))
    # timespan_text = textbox("1000")
    # map!(timespan_obs, observe(timespan_text)) do ts
        # parse(Int, ts)
    # end

    init_drop = dropdown(extrainit, value=extrainit[:init], label="Init")

    sim = button("sim")
    resume = button("resume")
    stop = button("stop")
    replay = button("replay")

    buttons = sim, resume, stop
    fps_slider = slider(1:200, value=fps(o), label="FPS")
    basewidgets = hbox(buttons..., fps_slider, init_drop)

    rulesliders = buildsliders(ruleset, throttle)


    # Put it all together into a webpage
    o.page = vbox(hbox(o.image_obs), timedisplay, basewidgets, rulesliders)

    # Initialise image
    image_obs[] = webimage(frametoimage(o, ruleset, o[1], 1))

    # Control mappings
    on(observe(sim)) do _
        sim!(o, ruleset; init=init_drop[], tspan=tspan)
    end
    on(observe(resume)) do _
        resume!(o, ruleset; tstop=last(tspan))
    end
    on(observe(replay)) do _
        replay(o)
    end
    on(observe(stop)) do _
        setrunning!(o, false)
    end
    on(observe(fps_slider)) do fps
        o.fps = fps
        settimestamp!(o, o.t_obs[])
    end

    return o
end

# Base interface
Base.display(o::InteractOutput) = display(o.page)
Base.show(o::InteractOutput) = show(o.page)

# DynamicGrids interface
DynamicGrids.isasync(o::InteractOutput) = true

DynamicGrids.showframe(image::AbstractArray{RGB24,2}, o::InteractOutput, f, t) = begin
    o.t_obs[] = f
    o.image_obs[] = webimage(image)
end


# Utils

buildsliders(ruleset, _throttle) = begin
    params = Flatten.flatten(rules(ruleset))
    fnames = fieldnameflatten(rules(ruleset))
    lims = metaflatten(rules(ruleset), FieldMetadata.limits)
    ranges = buildrange.(lims, params)
    parents = parentnameflatten(rules(ruleset))
    descriptions = metaflatten(rules(ruleset), FieldMetadata.description)
    attributes = (p, n, d) -> Dict(:title => "$p.$n: $d").(parents, fnames, descriptions)


    sliders = buildslider.(params, fnames, ranges, attributes)
    slider_obs = map((s...) -> s, throttle.(_throttle, observe.(sliders))...)
    on(slider_obs) do s
        ruleset.rules = Flatten.reconstruct(ruleset.rules, s)
        println(ruleset.rules)
    end

    group_title = nothing
    slider_groups = []
    group_items = []
    for i in 1:length(params)
        parent = parents[i]
        if group_title != parent
            group_title == nothing || push!(slider_groups, dom"div"(group_items...))
            group_items = Any[dom"h2"(string(parent))]
            group_title = parent
        end
        push!(group_items, sliders[i])
    end
    push!(slider_groups, dom"h2"(group_items...))

    vbox(slider_groups...)
end


buildslider(val, lab, rng, attr) = slider(rng; label=string(lab), value=val, attributes=attr)

buildrange(lim::Tuple{AbstractFloat,AbstractFloat}, val::T) where T =
    T(lim[1]):(T(lim[2])-T(lim[1]))/1000:T(lim[2])
buildrange(lim::Tuple{Int,Int}, val::T) where T = T(lim[1]):1:T(lim[2])

webimage(image) = dom"div"(image)
