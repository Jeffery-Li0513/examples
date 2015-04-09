! mc_lj_module.f90 (used by mc_nvt_lj.f90, mc_npt_lj.f90, mc_zvt_lj.f90)
! Monte Carlo simulation, Lennard-Jones atoms
MODULE mc_lj_module

  IMPLICIT NONE
  PRIVATE
  PUBLIC :: n, r, lt, ne, gt
  PUBLIC :: energy_1, energy, energy_lrc

  INTEGER                              :: n ! number of atoms
  REAL,    DIMENSION(:,:), ALLOCATABLE :: r ! positions (3,:)

  INTEGER, PARAMETER :: lt = -1, ne = 0, gt = 1 ! j-range options

CONTAINS

  SUBROUTINE energy ( sigma, r_cut, overlap, pot, vir, pot2, vir2 )
    REAL,                         INTENT(in)  :: sigma, r_cut ! potential parameters
    LOGICAL,                      INTENT(out) :: overlap      ! shows if an overlap was detected
    REAL,               OPTIONAL, INTENT(out) :: pot, vir     ! potential and virial 
    REAL, DIMENSION(2), OPTIONAL, INTENT(out) :: pot2, vir2   ! potential and virial parts 

    ! Calculates potential and virial for whole system
    ! If present, pot and vir contain the overall values 
    ! If present, pot2 and vir2 contain the separate components: LJ12 and LJ6 
    ! Includes a check for overlap (potential too high) to avoid overflow
    ! If overlap==.true., the values of pot and vir should not be used
    ! It is assumed that r, sigma and r_cut are in units where box = 1
    ! Results are in LJ units where sigma = 1, epsilon = 1

    REAL               :: pot_i, vir_i, pot_sum, vir_sum
    REAL, DIMENSION(2) :: pot2_i, vir2_i, pot2_sum, vir2_sum
    INTEGER            :: i

    IF ( n > SIZE(r,dim=2) ) STOP 'Array bounds error for r in energy'
    
    overlap  = .FALSE.
    pot_sum  = 0.0
    vir_sum  = 0.0
    pot2_sum = 0.0
    vir2_sum = 0.0

    DO i = 1, n - 1
       CALL energy_1 ( r(:,i), i, gt, sigma, r_cut, overlap, pot_i, vir_i, pot2_i, vir2_i )
       IF ( overlap ) EXIT ! jump out of loop
       pot_sum  = pot_sum  + pot_i
       vir_sum  = vir_sum  + vir_i
       pot2_sum = pot2_sum + pot2_i
       vir2_sum = vir2_sum + vir2_i
    END DO

    IF ( PRESENT ( pot  ) ) pot  = pot_sum
    IF ( PRESENT ( vir  ) ) vir  = vir_sum
    IF ( PRESENT ( pot2 ) ) pot2 = pot2_sum
    IF ( PRESENT ( vir2 ) ) vir2 = vir2_sum
    
  END SUBROUTINE energy

  SUBROUTINE energy_1 ( ri, i, j_range, sigma, r_cut, overlap, pot, vir, pot2, vir2 )

    REAL, DIMENSION(3),           INTENT(in)  :: ri           ! coordinates of atom of interest
    INTEGER,                      INTENT(in)  :: i, j_range   ! index, and partner index range
    REAL,                         INTENT(in)  :: r_cut, sigma ! LJ potential parameters
    LOGICAL,                      INTENT(out) :: overlap      ! shows if an overlap was detected
    REAL,               OPTIONAL, INTENT(out) :: pot, vir     ! potential and virial
    REAL, DIMENSION(2), OPTIONAL, INTENT(out) :: pot2, vir2   ! potential and virial parts

    ! Calculates potential energy and virial of atom in ri
    ! If present, pot and vir contain the overall values 
    ! If present, pot2 and vir2 contain the separate components: LJ12 and LJ6 
    ! with j/=i, j>i, or j<i depending on j_range
    ! Includes a check for overlap (potential too high) to avoid overflow
    ! If overlap==.true., the values of pot and vir should not be used
    ! It is assumed that r, sigma and r_cut are in units where box = 1
    ! Results are in LJ units where sigma = 1, epsilon = 1

    INTEGER            :: j, j1, j2
    REAL               :: r_cut_sq, sigma_sq
    REAL               :: sr2, sr6, rij_sq
    REAL, DIMENSION(2) :: pot2_sum, vir2_sum
    REAL, DIMENSION(3) :: rij
    REAL, PARAMETER    :: sr2_overlap = 1.8 ! overlap threshold

    IF ( n > SIZE(r,dim=2) ) STOP 'Array bounds error for r in energy_1'

    r_cut_sq = r_cut**2
    sigma_sq = sigma**2

    pot2_sum = 0.0
    vir2_sum = 0.0
    overlap = .FALSE.

    SELECT CASE ( j_range )
    CASE ( lt ) ! j < i
       j1 = 1
       j2 = i-1
    CASE ( gt ) ! j > i
       j1 = i+1
       j2 = n
    CASE ( ne ) ! j /= i
       j1 = 1
       j2 = n
    END SELECT

    DO j = j1, j2

       IF ( i == j ) CYCLE

       rij(:) = ri(:) - r(:,j)
       rij(:) = rij(:) - ANINT ( rij(:) ) ! periodic boundaries in box=1 units
       rij_sq = SUM ( rij**2 )

       IF ( rij_sq < r_cut_sq ) THEN

          sr2 = sigma_sq / rij_sq ! now dimensionless

          IF ( sr2 > sr2_overlap ) THEN
             overlap = .TRUE.
             EXIT ! jump out of loop
          END IF

          sr6         = sr2**3
          pot2_sum(1) = pot2_sum(1) + sr6**2
          pot2_sum(2) = pot2_sum(2) - sr6

       END IF

    END DO
    pot2_sum    = 4.0 * pot2_sum                   ! both LJ12 and LJ6 parts
    vir2_sum(1) = 12.0 * pot2_sum(1) / 3.0         ! LJ12 part
    vir2_sum(2) = 6.0  * pot2_sum(2) / 3.0         ! LJ6  part
    IF ( PRESENT ( pot  ) ) pot = SUM ( pot2_sum ) ! total
    IF ( PRESENT ( vir  ) ) vir = SUM ( vir2_sum ) ! total
    IF ( PRESENT ( pot2 ) ) pot2 = pot2_sum        ! separate parts
    IF ( PRESENT ( vir2 ) ) vir2 = vir2_sum        ! separate parts

  END SUBROUTINE energy_1

  SUBROUTINE energy_lrc ( n, sigma, r_cut, pot, vir, pot2, vir2 )
    INTEGER,                      INTENT(in)  :: n            ! number of atoms
    REAL,                         INTENT(in)  :: sigma, r_cut ! LJ potential parameters
    REAL,               OPTIONAL, INTENT(out) :: pot, vir     ! potential and virial
    REAL, DIMENSION(2), OPTIONAL, INTENT(out) :: pot2, vir2   ! potential and virial parts

    ! Calculates long-range corrections for Lennard-Jones potential and virial
    ! These are the corrections to the total values
    ! If present, pot and vir contain the overall values 
    ! If present, pot2 and vir2 contain the separate components: LJ12 and LJ6 
    ! It is assumed that sigma and r_cut are in units where box = 1
    ! Results are  in LJ units where sigma = 1, epsilon = 1
    
    REAL               :: sr3, density
    REAL, DIMENSION(2) :: pot2_lrc, vir2_lrc
    REAL, PARAMETER    :: pi = 4.0 * ATAN(1.0)

    sr3         = ( sigma / r_cut ) ** 3
    density     =  REAL(n)*sigma**3
    pot2_lrc(1) =  REAL(n)*(8.0/9.0)  * pi * density * sr3**3 ! LJ12 term
    pot2_lrc(2) = -REAL(n)*(8.0/3.0)  * pi * density * sr3    ! LJ6  term
    vir2_lrc(1) =  REAL(n)*(32.0/9.0) * pi * density * sr3**3 ! LJ12 term
    vir2_lrc(2) = -REAL(n)*(32.0/6.0) * pi * density * sr3    ! LJ6  term
    IF ( PRESENT ( pot  ) ) pot = SUM ( pot2_lrc )
    IF ( PRESENT ( vir  ) ) vir = SUM ( vir2_lrc )
    IF ( PRESENT ( pot2 ) ) pot2 = pot2_lrc
    IF ( PRESENT ( vir2 ) ) vir2 = vir2_lrc

  END SUBROUTINE energy_lrc

END MODULE mc_lj_module
