module OptimizationTest 

    using Plots
    using Printf
    using DifferentialEquations
    using ForwardDiff
    using Zygote
    using AbstractDifferentiation 
    using Optim
    using Statistics

    """
    Solve PDE with own ODE time integrator - Input is C₀ (IC)
    """
    function solve_pde(C::AbstractVector{T}) where {T}

        # Preallocate
        dC  =Zygote.Buffer(C,Nx)
        Cout=Zygote.Buffer(C,Nx)
        flux=Zygote.Buffer(C,Nx+1)

        # Initial condition
        t = 0.0
        
        # Determine timestep
        CFL=0.2
        dt=CFL*dx^2/D

        # Number of time iterations
        nStep=ceil(tfinal/dt)

        # Recompute dt with this nStep
        dt=tfinal/nStep

        for iter in 1:nStep
    
            # Update time
            t = t + dt

            # Compute fluxes = D*dC/dx
            flux[1]=0.0  # No flux at boundaries
            flux[Nx+1]=0.0
            for i=2:Nx
                flux[i] = D*(C[i] - C[i-1]) / dx
            end
            
            # Compute RHS dC/dt
            for i in 1:Nx
                dC[i]=(flux[i+1] - flux[i]) / dx
            end

            # Update C
            for i in 1:Nx
                Cout[i] = C[i] + dt * dC[i]
            end
            C=Cout
        end
        return copy(C)
    end

    """
    Define cost function to optimize (minimize)
    """
    function costFun(C₀)

        # Compute C using my ODE solver
        C=solve_pde(C₀)

        # Compute cost (error)
        cost=0.0
        for i in eachindex(C)
            cost = cost + ( C_goal[i] - C[i] )^2
            cost = cost + 1e-6(C₀[i]-mean(C₀))^2 # Add cost to large ICs
        end
        return cost
    end

    """
    Optimization - Gradient Descent & Newton's Method
    """
    function optimize_own(C₀)
        println("\nSolving Optimization Problem with Newton's Method and AD")
        α=1
        myplt = plot(C₀,label="Initial condition")
        iter=0
        converged = false
        ab = AD.ZygoteBackend()
        while converged == false
            iter += 1

            # Compute derivatives using AD
            # This is not working with Zygote!!!  
            (f, Grad, Hess) = AD.value_gradient_and_hessian(ab,costFun,C₀)

            # Compute function and derivatives individually
            f=costFun(C₀)
            Grad = Zygote.gradient(costFun,C₀)
            Hess = Zygote.hessian( costFun,C₀)

            # Compute new IC
            # if iter < 200 
                # Gradient descent 
            #    Cₙ = C₀ - α*Grad[1]
            # else
            #    # Newton's Method
                Cₙ = C₀ - α*(Hess\Grad[1])
            # end

            # Check if converged
            converged = (f < tol || iter == 500 || maximum(abs.(Grad[1])) < tol)

            # Transfer solution 
            C₀ = Cₙ

            # Output for current IC
            @printf(" %5i, Cost Function = %15.6g, max(∇) = %15.6g \n",iter,f,maximum(abs.(Grad[1]))) 
        end

        return C₀ # Optimized IC
    end

    """
    Optimization - Optim.jl
    """
    function optimize_Optim(C₀)
        println("\nSolving Optimization Problem with Optim and AD")

        # Uses automatic differentiation and Newton's Method
        od = TwiceDifferentiable(costFun, C₀; autodiff = :forward)
        Copt = Optim.minimizer(optimize(od, C₀, Newton(),
            Optim.Options(
                g_tol = tol,
                iterations = 1000,
                store_trace = false,
                show_trace = true)))
        myplt = plot!(Copt,label="Optimum IC from Optim.jl",m=:hexagon)
        display(myplt)
        return Copt # Optimized IC
    end

    """ 
    Heaviside Function
    """
    function heaviside(x)
        return map(x -> ifelse(x>=0.0,1.0,0.0),x)
    end
    
    """
    Main Driver
    """
    # Inputs
    tfinal = 2.0
    L = 2.0
    Nx = 20
    D=0.1
    tol = 1e-5

    # Grid
    x = range(0.0, L, length=Nx + 1)
    xm = 0.5 * (x[1:Nx] + x[2:Nx+1])
    dx = x[2] - x[1]

    # Create goal for final solution 
    ## Option 1
    #sigma=0.1; C₀=exp.(-(xm .- L / 2.0) .^ 2 / sigma) .+ 1.0
    ## Option 2
    C₀=heaviside(xm .- 0.51) - heaviside(xm .- 1.49)
    
    # Solve PDE to create realistic goal for optimizers
    C_goal=solve_pde(C₀)

    # Initial condition guess - used to start optimizers
    C₀_guess=ones(size(xm))

    # Optimize with own routine
    C₀_own = optimize_own(C₀_guess)

    # Optimize with Optim.jl
    C₀_optim = optimize_Optim(C₀_guess)

    # Plot specified and optimized ICs
    myplt = plot( xm,C₀,label="Specified IC used to make C_goal")
    myplt = plot!(xm,C₀_own,markershape=:circle,label="Own optimizer")
    myplt = plot!(xm,C₀_optim,linestyle=:dash,label="Optim.jl")
    myplt = plot!(title="Optimized Initial Condition")
    display(myplt)

    # Plot expected final solution (C_goal) 
    # and final solutions from optimized ICs
    myplt = plot( xm,C_goal,markershape=:square,label="C_goal")
    myplt = plot!(xm,solve_pde(C₀_own),markershape=:circle,label="Own optimizer (Zygote)")
    myplt = plot!(xm,solve_pde(C₀_optim),linestyle=:dash,label="Optim.jl (ForwardDiff)")
    myplt = plot!(title="Final solution using optimized Initial Condition")
    display(myplt)

end

