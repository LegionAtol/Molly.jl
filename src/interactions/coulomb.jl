export
    Coulomb,
    CoulombSoftCore,
    CoulombReactionField

@doc raw"""
    Coulomb(; cutoff, use_neighbors, weight_special, coulomb_const, force_units, energy_units)

The Coulomb electrostatic interaction between two atoms.

The potential energy is defined as
```math
V(r_{ij}) = \frac{q_i q_j}{4 \pi \varepsilon_0 r_{ij}}
```
"""
struct Coulomb{C, W, T, F, E} <: PairwiseInteraction
    cutoff::C
    use_neighbors::Bool
    weight_special::W
    coulomb_const::T
    force_units::F
    energy_units::E
end

const coulombconst = 138.93545764u"kJ * mol^-1 * nm" # 1 / 4πϵ0

function Coulomb(;
                    cutoff=NoCutoff(),
                    use_neighbors=false,
                    weight_special=1,
                    coulomb_const=coulombconst,
                    force_units=u"kJ * mol^-1 * nm^-1",
                    energy_units=u"kJ * mol^-1")
    return Coulomb{typeof(cutoff), typeof(weight_special), typeof(coulomb_const), typeof(force_units), typeof(energy_units)}(
        cutoff, use_neighbors, weight_special, coulomb_const, force_units, energy_units)
end

use_neighbors(inter::Coulomb) = inter.use_neighbors

function Base.zero(coul::Coulomb{C, W, T, F, E}) where {C, W, T, F, E}
    return Coulomb{C, W, T, F, E}(
        coul.cutoff,
        false,
        zero(W),
        zero(T),
        coul.force_units,
        coul.energy_units,
    )
end

function Base.:+(c1::Coulomb, c2::Coulomb)
    return Coulomb(
        c1.cutoff,
        c1.use_neighbors,
        c1.weight_special + c2.weight_special,
        c1.coulomb_const + c2.coulomb_const,
        c1.force_units,
        c1.energy_units,
    )
end

@inline function force(inter::Coulomb{C},
                                    dr,
                                    coord_i,
                                    coord_j,
                                    atom_i,
                                    atom_j,
                                    boundary,
                                    special::Bool=false) where C
    r2 = sum(abs2, dr)
    cutoff = inter.cutoff
    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge
    params = (coulomb_const, qi, qj)

    f = force_divr_with_cutoff(inter, r2, params, cutoff, coord_i, inter.force_units)
    if special
        return f * dr * inter.weight_special
    else
        return f * dr
    end
end

function force_divr(::Coulomb, r2, invr2, (coulomb_const, qi, qj))
    return (coulomb_const * qi * qj) / √(r2 ^ 3)
end

@inline function potential_energy(inter::Coulomb{C},
                                            dr,
                                            coord_i,
                                            coord_j,
                                            atom_i,
                                            atom_j,
                                            boundary,
                                            special::Bool=false) where C
    r2 = sum(abs2, dr)
    cutoff = inter.cutoff
    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge
    params = (coulomb_const, qi, qj)

    pe = potential_with_cutoff(inter, r2, params, cutoff, coord_i, inter.energy_units)
    if special
        return pe * inter.weight_special
    else
        return pe
    end
end

function potential(::Coulomb, r2, invr2, (coulomb_const, qi, qj))
    return (coulomb_const * qi * qj) * √invr2
end

@doc raw"""
    CoulombSoftCore(; cutoff, α, λ, p, use_neighbors, lorentz_mixing, weight_special,
                    coulomb_const, force_units, energy_units)

The Coulomb electrostatic interaction between two atoms with a soft core.

The potential energy is defined as
```math
V(r_{ij}) = \frac{q_i q_j}{4 \pi \varepsilon_0 (r_{ij}^6 + \alpha  \sigma_{ij}^6  \lambda^p)^{\frac{1}{6}}}
```
If ``\alpha`` or ``\lambda`` are zero this gives the standard [`Coulomb`](@ref) potential.
"""
struct CoulombSoftCore{C, A, L, P, R, W, T, F, E} <: PairwiseInteraction
    cutoff::C
    α::A
    λ::L
    p::P
    σ6_fac::R
    use_neighbors::Bool
    lorentz_mixing::Bool
    weight_special::W
    coulomb_const::T
    force_units::F
    energy_units::E
end

function CoulombSoftCore(;
                    cutoff=NoCutoff(),
                    α=1,
                    λ=0,
                    p=2,
                    use_neighbors=false,
                    lorentz_mixing=true,
                    weight_special=1,
                    coulomb_const=coulombconst,
                    force_units=u"kJ * mol^-1 * nm^-1",
                    energy_units=u"kJ * mol^-1")
    σ6_fac = α * λ^p
    return CoulombSoftCore{typeof(cutoff), typeof(α), typeof(λ), typeof(p), typeof(σ6_fac),
                           typeof(weight_special), typeof(coulomb_const), typeof(force_units),
                           typeof(energy_units)}(
        cutoff, α, λ, p, σ6_fac, use_neighbors, lorentz_mixing, weight_special, coulomb_const,
        force_units, energy_units)
end

use_neighbors(inter::CoulombSoftCore) = inter.use_neighbors

@inline function force(inter::CoulombSoftCore{C},
                                    dr,
                                    coord_i,
                                    coord_j,
                                    atom_i,
                                    atom_j,
                                    boundary,
                                    special::Bool=false) where C
    r2 = sum(abs2, dr)
    cutoff = inter.cutoff
    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge
    σ = inter.lorentz_mixing ? (atom_i.σ + atom_j.σ) / 2 : sqrt(atom_i.σ * atom_j.σ)
    params = (coulomb_const, qi, qj, σ, inter.σ6_fac)

    f = force_divr_with_cutoff(inter, r2, params, cutoff, coord_i, inter.force_units)
    if special
        return f * dr * inter.weight_special
    else
        return f * dr
    end
end

function force_divr(::CoulombSoftCore, r2, invr2, (coulomb_const, qi, qj, σ, σ6_fac))
    inv_rsc6 = inv(r2^3 + σ6_fac * σ^6)
    inv_rsc2 = cbrt(inv_rsc6)
    inv_rsc3 = sqrt(inv_rsc6)
    ff = (coulomb_const * qi * qj) * inv_rsc2 * sqrt(r2)^5 * inv_rsc2 * inv_rsc3
    return ff * √invr2
end

@inline function potential_energy(inter::CoulombSoftCore{C},
                                            dr,
                                            coord_i,
                                            coord_j,
                                            atom_i,
                                            atom_j,
                                            boundary,
                                            special::Bool=false) where C
    r2 = sum(abs2, dr)
    cutoff = inter.cutoff
    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge
    σ = inter.lorentz_mixing ? (atom_i.σ + atom_j.σ) / 2 : sqrt(atom_i.σ * atom_j.σ)
    params = (coulomb_const, qi, qj, σ, inter.σ6_fac)

    pe = potential_with_cutoff(inter, r2, params, cutoff, coord_i, inter.energy_units)
    if special
        return pe * inter.weight_special
    else
        return pe
    end
end

function potential(::CoulombSoftCore, r2, invr2, (coulomb_const, qi, qj, σ, σ6_fac))
    inv_rsc6 = inv(r2^3 + σ6_fac * σ^6)
    return (coulomb_const * qi * qj) * √cbrt(inv_rsc6)
end

"""
    CoulombReactionField(; dist_cutoff, solvent_dielectric, use_neighbors, weight_special,
                            coulomb_const, force_units, energy_units)

The Coulomb electrostatic interaction modified using the reaction field approximation
between two atoms.
"""
struct CoulombReactionField{D, S, W, T, F, E} <: PairwiseInteraction
    dist_cutoff::D
    solvent_dielectric::S
    use_neighbors::Bool
    weight_special::W
    coulomb_const::T
    force_units::F
    energy_units::E
end

const crf_solvent_dielectric = 78.3

function CoulombReactionField(;
                    dist_cutoff,
                    solvent_dielectric=crf_solvent_dielectric,
                    use_neighbors=false,
                    weight_special=1,
                    coulomb_const=coulombconst,
                    force_units=u"kJ * mol^-1 * nm^-1",
                    energy_units=u"kJ * mol^-1")
    return CoulombReactionField{typeof(dist_cutoff), typeof(solvent_dielectric), typeof(weight_special),
                                typeof(coulomb_const), typeof(force_units), typeof(energy_units)}(
        dist_cutoff, solvent_dielectric, use_neighbors, weight_special,
        coulomb_const, force_units, energy_units)
end

use_neighbors(inter::CoulombReactionField) = inter.use_neighbors

function Base.zero(coul::CoulombReactionField{D, S, W, T, F, E}) where {D, S, W, T, F, E}
    return CoulombReactionField{D, S, W, T, F, E}(
        zero(D),
        zero(S),
        false,
        zero(W),
        zero(T),
        coul.force_units,
        coul.energy_units,
    )
end

function Base.:+(c1::CoulombReactionField, c2::CoulombReactionField)
    return CoulombReactionField(
        c1.dist_cutoff + c2.dist_cutoff,
        c1.solvent_dielectric + c2.solvent_dielectric,
        c1.use_neighbors,
        c1.weight_special + c2.weight_special,
        c1.coulomb_const + c2.coulomb_const,
        c1.force_units,
        c1.energy_units,
    )
end

@inline function force(inter::CoulombReactionField,
                                    dr,
                                    coord_i,
                                    coord_j,
                                    atom_i,
                                    atom_j,
                                    boundary,
                                    special::Bool=false)
    r2 = sum(abs2, dr)
    if r2 > (inter.dist_cutoff ^ 2)
        return ustrip.(zero(coord_i)) * inter.force_units
    end

    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge
    r = √r2
    if special
        # 1-4 interactions do not use the reaction field approximation
        krf = (1 / (inter.dist_cutoff ^ 3)) * 0
    else
        # These values could be pre-computed but this way is easier for AD
        krf = (1 / (inter.dist_cutoff ^ 3)) * ((inter.solvent_dielectric - 1) /
              (2 * inter.solvent_dielectric + 1))
    end

    f = (coulomb_const * qi * qj) * (inv(r) - 2 * krf * r2) * inv(r2)

    if special
        return f * dr * inter.weight_special
    else
        return f * dr
    end
end

@inline function potential_energy(inter::CoulombReactionField,
                                            dr,
                                            coord_i,
                                            coord_j,
                                            atom_i,
                                            atom_j,
                                            boundary,
                                            special::Bool=false)
    r2 = sum(abs2, dr)
    if r2 > (inter.dist_cutoff ^ 2)
        return ustrip(zero(coord_i[1])) * inter.energy_units
    end

    coulomb_const = inter.coulomb_const
    qi, qj = atom_i.charge, atom_j.charge
    r = √r2
    if special
        # 1-4 interactions do not use the reaction field approximation
        krf = (1 / (inter.dist_cutoff ^ 3)) * 0
        crf = (1 /  inter.dist_cutoff     ) * 0
    else
        krf = (1 / (inter.dist_cutoff ^ 3)) * ((inter.solvent_dielectric - 1) /
              (2 * inter.solvent_dielectric + 1))
        crf = (1 /  inter.dist_cutoff     ) * ((3 * inter.solvent_dielectric) / 
              (2 * inter.solvent_dielectric + 1))
    end

    pe = (coulomb_const * qi * qj) * (inv(r) + krf * r2 - crf)

    if special
        return pe * inter.weight_special
    else
        return pe
    end
end
