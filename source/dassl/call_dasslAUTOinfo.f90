! 8-JUL-09 mrharper: added Lindemann reactions
! 6/25/08 gmagoon: removed comments for debugging/timing
! 5/14/08 gmagoon: filename: call_dasslAUTOdebug.f90 (includes output used
! for debugging)
! 4/25/08 gmagoon: changed name from CALL_DASPK (sic) to CALL_DASSLAUTO
! to indicate that this version requires changes to RMG
! 4/26/08 gmagoon: changed from .f to .f90 and from "C" comments to "!"
! comments to address compilation issues; also changed "$" continued line
! to "& /n &" continued line
      PROGRAM CALL_DASSLAUTO

      IMPLICIT NONE

! IN THIS CODE WE ASSUME THAT THE 
! MAXIMUM # SPECIES = 1500 
! MAXIMUM # REACTIONS = 100,000
! MAXIMUM # THIRDBODYREACTIONS = 100
! MAXIMUM # TROEREACTIONS = 100
! MAXIMUM # LINDEMANNREACTIONS = 100

      INTEGER SPMAX, RMAX, TBRMAX, TROEMAX, LINDEMAX
      PARAMETER (SPMAX = 1500, RMAX = 100000, TBRMAX=100, TROEMAX=100, LINDEMAX=100)

      INTEGER NSTATE, INFO(30), IWORK(1541), LRW, LIW, NEQ, &
     &     REACTIONSIZE, THIRDBODYREACTIONSIZE, TROEREACTIONSIZE, &
     &     REACTIONARRAY(9*RMAX), THIRDBODYREACTIONARRAY(20*TBRMAX), &
     &     TROEREACTIONARRAY(21*TROEMAX), I, J, IDID, impspecies, &
     &     AUTOFLAG, ESPECIES, EREACTIONSIZE, ConstantConcentration(SPMAX+1), &
     &     LINDEREACTIONSIZE, LINDEREACTIONARRAY(20*LINDEMAX)

      DOUBLE PRECISION Y(SPMAX), YPRIME(SPMAX), T, TOUT, RTOL, ATOL,&
     &     RWORK(51+9*SPMAX+SPMAX**2), TEMPERATURE, PRESSURE,&
     &     REACTIONRATEARRAY(5*rmax),&
     &     THIRDBODYREACTIONRATEARRAY(16*Tbrmax),&
     &     TROEREACTIONRATEARRAY(21*TROemax), targetconc, THRESH, &
     &     LINDEREACTIONRATEARRAY(17*LINDEMAX)
     ! 4/25/08 gmagoon:make auto arrays allocatable and double
     ! precision for KVEC
     INTEGER, DIMENSION(:), ALLOCATABLE :: NEREAC,NEPROD
     INTEGER, DIMENSION(:,:), ALLOCATABLE :: IDEREAC, IDEPROD
     DOUBLE PRECISION, DIMENSION(:), ALLOCATABLE :: KVEC

      COMMON /SIZE/ NSTATE, REACTIONSIZE, THIRDBODYREACTIONSIZE,&
     &     TROEREACTIONSIZE, LINDEREACTIONSIZE

      COMMON /REAC/ REACTIONRATEARRAY, THIRDBODYREACTIONRATEARRAY,&
     &     TROEREACTIONRATEARRAY, temperature, pressure,&
     &     REACTIONARRAY, THIRDBODYREACTIONARRAY,&
     &     TROEREACTIONARRAY, ConstantConcentration, &
     &     LINDEREACTIONRATEARRAY, LINDEREACTIONARRAY
!5/12/08 gmagoon: added timing (cf. http://beige.ucs.indiana.edu/B673/node105.html)
!      integer count_0, count_1, count_rate, count_max
!      double precision start, finish
!      call system_clock(count_0, count_rate, count_max)
!      start = count_0 * 1.0 / count_rate

      OPEN (UNIT=12, FILE = 'SolverInput.dat', STATUS = 'OLD')
      OPEN(UNIT=25, FILE='CoreConc.dat')
      OPEN(UNIT=30, FILE='EdgeFlux.dat')
      OPEN(UNIT=40, FILE='EdgeReacFlux.dat')

! READ THE NUMBER OF SPECIES; 4/24/08 gmagoon: added autoFlag,
! which will equal 1 for automatic (solve ODE until flux
! exceeds threshhold) or -1 for conventional operation
! (i.e. user-specification of time/conversion steps) 
      READ(12,*) NSTATE, NEQ, IMPSPECIES, TARGETCONC, AUTOFLAG
      NSTATE = NSTATE+1
      
!  READ THE CONCENTRATIONS
      READ(12,*) (Y(I), i=1,nstate-1)

! READ THE RATE OF CHANGE OF CONCENTRATIONS
      READ(12,*) (YPRIME(I), i=1,nstate-1)
      YPRIME(NSTATE) = 0;

! READ THE TIME AND TOUT
      READ(12,*) T, TOUT

! READ THE INFO ARRAY
      READ(12,*) (INFO(I), I=1,30)

! READ RTOL AND ATOL
      READ(12,*) RTOL, ATOL

! READ TEMPERATURE AND PRESSURE
      READ(12,*) TEMPERATURE, PRESSURE

      Y(NSTATE) = 8.314*temperature/pressure/1e-6;
      do i=1,nstate-1
         y(i) = y(i)*y(nstate)
         !write(20,*) i, 0, y(i)
      end do



! READ INFORMATION ABOUT REACTIONS
      READ(12,*) REACTIONSIZE
      READ(12,*) (REACTIONARRAY(I),I=1,9*REACTIONSIZE)
      READ(12,*) (REACTIONRATEARRAY(I),I=1,5*REACTIONSIZE)

! READ INFORMATION ABOUT THIRDBODYREACTIONS
      READ(12,*) THIRDBODYREACTIONSIZE
      READ(12,*)(THIRDBODYREACTIONARRAY(I),I=1,20*THIRDBODYREACTIONSIZE)
      READ(12,*)(THIRDBODYREACTIONRATEARRAY(I),I=1, &
    &  16*THIRDBODYREACTIONSIZE)
      
! READ INFORMATION ABOUT TROEREACTIONS
      READ(12,*) TROEREACTIONSIZE
      READ(12,*)(TROEREACTIONARRAY(I),I=1,21*TROEREACTIONSIZE)
      READ(12,*)(TROEREACTIONRATEARRAY(I),I=1,21*TROEREACTIONSIZE)

! READ INFORMATION ABOUT LINDEMANNREACTIONS
      READ(12,*) LINDEREACTIONSIZE
      READ(12,*)(LINDEREACTIONARRAY(I),I=1,20*LINDEREACTIONSIZE)
      READ(12,*)(LINDEREACTIONRATEARRAY(I),I=1,17*LINDEREACTIONSIZE)

! 4/24/08 gmagoon: if autoFlag = 1, read in additional information 
! specific to automatic time stepping
    IF (AUTOFLAG .EQ. 1) THEN
        ! read the threshhold, corresponding to the value
        ! specified in condition.txt input file
        READ(12,*) THRESH
        ! read the number of edge species and edge reactions
        READ(12,*) ESPECIES, EREACTIONSIZE
        ! allocate memory for arrays
        ALLOCATE(NEREAC(EREACTIONSIZE), NEPROD(EREACTIONSIZE),&
    &       IDEREAC(EREACTIONSIZE,3), IDEPROD(EREACTIONSIZE,3),&
    &            KVEC(EREACTIONSIZE))
        ! read in the reaction parameters for each reaction;
        ! a maximum of 3 products and 3 reactants is assumed
        ! for each reaction; parameters read for each reaction
        ! are: number of reactants, number of products,
        ! three reactant ID's (integers from 1 to NSTATE-1),
        ! three product ID's (integers from 1 to ESPECIES),
        ! and the rate coefficient k, such that dCi/dt=k*Ca*Cb;
        ! note that cases where abs. value of stoic. coeff. 
        ! does not equal one are handled by using repeated
        ! reactant/product IDs
        ! note: use of KVEC rather than Arrhenius parameters
        ! requires assumption that system is isothermal
        ! (and isobaric for pressure dependence)
        DO I=1, EREACTIONSIZE
            READ(12,*) NEREAC(I),NEPROD(I),IDEREAC(I,1), & 
         &            IDEREAC(I,2),IDEREAC(I,3),IDEPROD(I,1), &
         &            IDEPROD(I,2), IDEPROD(I,3), KVEC(I)
        ! alternative for reading Arrhenius parameters instead
        ! of k values; this allows easier extention to
        ! non-isothermal systems in the future
        ! form: k=A*T^n*e^(Ea/(RT)) *?
        ! units: A[=], n[=]dimensionless, Ea[=]
      !     READ(12,*) NEREAC(I),NEPROD(I),IDEREAC(I,1), &
        ! &               IDEREAC(I,2),IDEREAC(I,3),IDEPROD(I,1), &
        ! &               IDEPROD(I,2),IDEPROD(I,3), AVEC(I), NVEC(I), &
        ! &               EAVEC(I)
    !      for isothermal, isobaric systems, (or just isothermal 
    !      systems if pressure dependence is not considered)
      !      the following may be calculated here once
    !      (versus calculating at every timestep)
    !      ...units may need adjustment:
    !           KVEC(I)=AVEC(I)*TEMPERATURE**NVEC(I)*EXP(EAVEC(I) &
    !   &       /(8.314*TEMPERATURE))
        END DO
    END IF
    
    ! read constantConcentration data (if flag = 1 then the concentration of that species will not be integrated)
    ! there is one integer for each species (up to nstate-1), then the last one is for the VOLUME
    READ(12,*) (ConstantConcentration(I), i=1,nstate)


! READ RWORK AND IWORK
      IF (T .NE. 0.0) THEN
         OPEN(UNIT=13, FILE = 'RWORK.DAT', FORM='UNFORMATTED')
         READ(13) (RWORK(I),I=1,51+9*NSTATE+NSTATE**2)

         OPEN(UNIT=14, FILE = 'IWORK.DAT', FORM='UNFORMATTED')
         READ(14) (IWORK(I),I=1, 41+NSTATE)
      END IF
      !5/13/08 gmagoon: close 13 and 14 to avoid "File already opened
      ! in another unit" error when T.NE.0 (occurs when we want to
      ! write to files later on); I'm surprised this was not
      ! a problem before my modifications...it may have to do with
      ! Fortran90 vs. Fortran 77; perhaps it was a problem with
      ! non-auto cases after my modifications and I just didn't
      ! notice it
     CLOSE(13)
         CLOSE(14)

      CALL SOLVEODE(Y, YPRIME, T, TOUT, INFO, RTOL, ATOL, IDID, &
     &     RWORK, IWORK, IMPSPECIES, TARGETCONC, AUTOFLAG, &
     &     THRESH,ESPECIES,EREACTIONSIZE,NEREAC,NEPROD,IDEREAC, &
     &     IDEPROD,KVEC)

! 4/25/08 gmagoon: deallocate memory from allocatable arrays
! (may or may not be useful)
! 5/12/08 gmagoon: changed to only deallocate if autoflag=1
! this should prevent "deallocated a bad pointer" error when
! autoflag is not 1
      IF (AUTOFLAG .EQ. 1) THEN
        DEALLOCATE (NEREAC, NEPROD, KVEC, &
     &  IDEREAC, IDEPROD)
      END IF

      !5/12/08 gmagoon: added timing (see above)
    !  call system_clock(count_1, count_rate, count_max)
    !  finish = count_1 * 1.0 / count_rate
      !5/13/08 gmagoon: just printing value for easier reading by Java
      ! this value will come last (following time-stepping time and 
      ! "ODE successful" message)
      !write(*,*) 'Fortran timing: ', (finish-start)
     ! write(*,*) (finish-start)
      CLOSE(25)
      CLOSE(30)
      CLOSE(40)
      END PROGRAM CALL_DASSLAUTO


      SUBROUTINE JAC()
      END SUBROUTINE JAC

! gmagoon 4/24/08: added vars needed as parameters for automatic
! time stepping
      SUBROUTINE SOLVEODE(Y, YPRIME, Time, TOUT, INFO, RTOL, ATOL, &
     &     IDID, RWORK, IWORK, IMPSPECIES, TARGETCONC, AUTOFLAG, &
     &     THRESH,ESPECIES,EREACTIONSIZE,NEREAC,NEPROD,IDEREAC, &
     &     IDEPROD,KVEC)

      IMPLICIT NONE
      
!     INITIALIZE VARIABLES IN COMMON BLOC
      INTEGER SPMAX, RMAX, TBRMAX, TROEMAX, AUTOFLAG, ESPECIES, &
    & EREACTIONSIZE, LINDEMAX
      INTEGER NEREAC(EREACTIONSIZE),NEPROD(EREACTIONSIZE)
      INTEGER IDEREAC(EREACTIONSIZE,3), IDEPROD(EREACTIONSIZE,3)
      DOUBLE PRECISION KVEC(EREACTIONSIZE)

      PARAMETER (SPMAX = 1500, RMAX = 100000, TBRMAX=100, TROEMAX=100, &
      &    LINDEMAX=100)

      INTEGER REACTIONSIZE, THIRDBODYREACTIONSIZE, TROEREACTIONSIZE, &
     &     REACTIONARRAY(9*RMAX), THIRDBODYREACTIONARRAY(20*TBRMAX), &
     &     TROEREACTIONARRAY(21*TROEMAX), I, J, NSTATE, EDGEFLAG,    &
     &     ConstantConcentration(SPMAX+1), LINDEREACTIONSIZE, &
     &     LINDEREACTIONARRAY(20*LINDEMAX)

      DOUBLE PRECISION REACTIONRATEARRAY(5*rmax), &
     &     THIRDBODYREACTIONRATEARRAY(16*Tbrmax), &
     &     TROEREACTIONRATEARRAY(21*TROemax), TEMPERATURE, PRESSURE, &
     &     THRESH, LINDEREACTIONRATEARRAY(17*LINDEMAX)

      COMMON /SIZE/ NSTATE, REACTIONSIZE, THIRDBODYREACTIONSIZE, &
     &     TROEREACTIONSIZE, LINDEREACTIONSIZE

      COMMON /REAC/ REACTIONRATEARRAY, THIRDBODYREACTIONRATEARRAY,&
     &     TROEREACTIONRATEARRAY, temperature, pressure,&
     &     REACTIONARRAY, THIRDBODYREACTIONARRAY,&
     &     TROEREACTIONARRAY, ConstantConcentration, &
     &     LINDEREACTIONRATEARRAY, LINDEREACTIONARRAY

      INTEGER  INFO(30), LIW, LRW, IWORK(*), IPAR(1),IDID, iter, &
     &     IMPSPECIES, conc
      DOUBLE PRECISION Y(NSTATE), YPRIME(NSTATE), Time, TOUT, RTOL, ATOL &
     &     , RWORK(*), TARGETCONC

      DOUBLE PRECISION RPAR(REACTIONSIZE+THIRDBODYREACTIONSIZE+ &
     &     TROEREACTIONSIZE+LINDEREACTIONSIZE),&
     &     TotalReactionFlux(REACTIONSIZE+THIRDBODYREACTIONSIZE+ &
     &     TROEREACTIONSIZE+LINDEREACTIONSIZE),&
     &     CURRENTReactionFlux(REACTIONSIZE+THIRDBODYREACTIONSIZE+ &
     &     TROEREACTIONSIZE+LINDEREACTIONSIZE),&
     &     PREVReactionFlux(REACTIONSIZE+THIRDBODYREACTIONSIZE+&
     &     TROEREACTIONSIZE+LINDEREACTIONSIZE), PREVTIME

      EXTERNAL RES, JAC, GETFLUX
    ! 5/13/08 gmagoon: vars for timing
    !  integer count_0T, count_1T, count_rateT, count_maxT
    !  double precision startT, finishT

      conc = 1
      IPAR(1)= NSTATE

      LIW = 41 + NSTATE
      LRW = 51 + 9*NSTATE + NSTATE**2

!     ******* INITIALIZE THE REAL ARRAY
      DO I=0,REACTIONSIZE-1
         RPAR(I+1) = REACTIONRATEARRAY(5*I+1)
      END DO

      DO I=0,THIRDBODYREACTIONSIZE-1
         RPAR(REACTIONSIZE+I+1) = THIRDBODYREACTIONRATEARRAY(16*I+1)
      END DO

      DO I=0,TROEREACTIONSIZE-1
         RPAR(REACTIONSIZE+THIRDBODYREACTIONSIZE+I+1) = &
     &        TROEREACTIONRATEARRAY(21*I+1)
      END DO

      DO I=0,LINDEREACTIONSIZE-1
         RPAR(REACTIONSIZE+THIRDBODYREACTIONSIZE+TROEREACTIONSIZE+I+1) = &
     &        LINDEREACTIONRATEARRAY(17*I+1)
      END DO
!     **********************************
! 5/13/08 gmagoon: added time stepping timing
   !   call system_clock(count_0T, count_rateT, count_maxT)
   !   startT = count_0T * 1.0 / count_rateT


      CALL GETFLUX(Y, YPRIME, RPAR)
    
! 4/24/08 gmagoon: call EdgeFlux if AUTOFLAG is 1 to
! determine EDGEFLAG (-1 if flux threshhold has not been met,
! positive integer otherwise)
    EDGEFLAG = -1
    IF (AUTOFLAG.eq.1) THEN
        CALL EDGEFLUX(EDGEFLAG, Y, YPRIME,THRESH,ESPECIES, &
     &     EREACTIONSIZE,NEREAC,NEPROD,IDEREAC,IDEPROD,KVEC, &
     &     NSTATE,time)
    ENDIF

      iter = 0;
      PREVTIME = TIME
      DO I=1,REACTIONSIZE+THIRDBODYREACTIONSIZE+TROEREACTIONSIZE+LINDEREACTIONSIZE
         PREVREACTIONFLUX(I) = 0
         TOTALREACTIONFLUX(I) = 0
         CURRENTREACTIONFLUX(I) = 0
      END DO
      call Reaction_flux(y, prevreactionflux, rpar)
      
      IF (IMPSPECIES .EQ. -1) THEN
         TARGETCONC = -1E10
         IMPSPECIES = 1
         conc = -1
      END IF
    

! 4/24/08 gmagoon: added criteria that edgeflag = -1 for loop to
! continue; calls to DASSL will stop once EDGEFLAG takes on a
! different value
 1    IF (Time .LE. TOUT .AND. Y(IMPSPECIES) .GE. TARGETCONC*Y(NSTATE) &
     &    .AND. EDGEFLAG .EQ. -1) &
     &     THEN

         CALL DDASSL(RES, NSTATE, Time, Y, YPRIME, TOUT, INFO, RTOL, &
     &        Atol, IDID, RWORK, LRW, IWORK, LIW, RPAR, IPAR, JAC)
!         WRITE(*,*) Time, Tout
         IF (IDID .EQ. -1) THEN
            WRITE(*,*) "Warning: 500 steps were already taken, taking &
     &           another 500 steps"
            INFO(1) = 1
            GO TO 1
         ELSE IF ( IDID .EQ. 1) THEN
            iter = iter + 1
            CALL REACTION_FLUX(Y, CURRENTREACTIONFLUX, RPAR)

            DO I=1,REACTIONSIZE+THIRDBODYREACTIONSIZE+TROEREACTIONSIZE+LINDEREACTIONSIZE
               TOTALREACTIONFLUX(I) = TOTALREACTIONFLUX(I) + &
     &              (CURRENTREACTIONFLUX(I) + PREVREACTIONFLUX(I)) * &
     &              (TIME - PREVTIME)/2
               PREVREACTIONFLUX(I) = CURRENTREACTIONFLUX(I)
            END DO
            PREVTIME = TIME
            if (conc .eq. 1 .AND. Time .le. 1E6) then
               tout = 200*time
            end if
!            write(*,*) time, y(impspecies), targetConc*y(nstate)
    ! 4/24/08 gmagoon: call EdgeFlux if AUTOFLAG is 1 to
    ! determine EDGEFLAG 
        IF (AUTOFLAG.eq.1) THEN
            CALL EDGEFLUX(EDGEFLAG, Y, YPRIME,THRESH,ESPECIES, &
             &     EREACTIONSIZE,NEREAC,NEPROD,IDEREAC,IDEPROD,KVEC, &
         &     NSTATE,time)
        ENDIF
            GO TO 1
         END IF
      END IF
      !5/13/08 gmagoon: added timing (see above)
     ! call system_clock(count_1T, count_rateT, count_maxT)
     ! finishT = count_1T * 1.0 / count_rateT
      !write(*,*) 'Time-stepping timing: ', (finishT-startT)
     ! write(*,*) (finishT-startT)

      OPEN(UNIT=16, FILE='SolverOutput.dat')

      write(16,*) iter
      WRITE(16,*) NSTATE-1
      write(16,*) time
      DO I=1,NSTATE-1
         WRITE(16,*) Y(I)/Y(NSTATE)
      END DO
      

      DO I=1,NSTATE-1
   ! 5/9/08 gmagoon: these values are read by RMG as flux; corrected to
   ! include volume changing effects (dV/dt) using quotient rule
   !      WRITE(16,*) YPRIME(I)/Y(NSTATE)
          WRITE(16,*) (Y(NSTATE)*YPRIME(I)-Y(I)*YPRIME(NSTATE))/(Y(NSTATE)**2)
      END DO

      DO I=1,REACTIONSIZE+THIRDBODYREACTIONSIZE+TROEREACTIONSIZE+LINDEREACTIONSIZE
         WRITE(16,*) TOTALREACTIONFLUX(I)
      END DO
      
      write(16,*) y(nstate)

      CLOSE(16)

      OPEN(UNIT=14, FILE='RWORK.DAT', FORM='UNFORMATTED')
      WRITE(14) (RWORK(I),I=1,LRW)
      CLOSE(14)

      OPEN(UNIT=15, FILE='IWORK.DAT', FORM='UNFORMATTED')
      WRITE(15) (IWORK(I),I=1,LIW)
      CLOSE(15)
      
      if (idid .eq. 1 .or. idid .eq. 2 .or. idid .eq. 3) then
         WRITE(*,*) "******ODESOLVER SUCCESSFUL: IDID=",idid
      else
         WRITE(*,*) "******ODESOLVER FAILED : IDID=", idid
      end if
!      write(*,*) yprime(nstate)
      END SUBROUTINE SOLVEode
            

! 4/24/08 gmagoon: adding subroutines EDGEFLUX and RCHAR

! EDGEFLUX determines whether threshhold flux has been
! reached by any species; if so, EDGEFLAG is set to a
! value besides -1; otherwise, EDGEFLAG remains -1;
! EDGEFLUX also calls RCHAR
SUBROUTINE EDGEFLUX(EDGEFLAG, Y, YPRIME,THRESH,ESPECIES, &
             &     EREACTIONSIZE,NEREAC,NEPROD,IDEREAC,IDEPROD, &
        &      KVEC, NSTATE,T)
    IMPLICIT NONE
    INTEGER EDGEFLAG, ESPECIES, EREACTIONSIZE, NSTATE, I, J, K
    DOUBLE PRECISION THRESH, FLUXRC, RFLUX, Y(NSTATE), YPRIME(NSTATE), T
    DOUBLE PRECISION, DIMENSION(:), ALLOCATABLE :: RATE
    INTEGER NEREAC(EREACTIONSIZE),NEPROD(EREACTIONSIZE)
        INTEGER IDEREAC(EREACTIONSIZE,3), IDEPROD(EREACTIONSIZE,3)
        DOUBLE PRECISION KVEC(EREACTIONSIZE)
    
    ALLOCATE(RATE(ESPECIES))
    ! initialize array to have all zeroes
    RATE=0
    ! it is assumed edgeflag = -1 at this point, since
      ! this should be the only way to access this subroutine

      ! calculate characteristic flux, FLUXRC
    CALL RCHAR(FLUXRC, Y, YPRIME, NSTATE)

    ! calculate the vector of fluxes for each species
    ! by summing contributions from each reaction
    ILOOP: DO I=1, EREACTIONSIZE
          ! calculate reaction flux by multiplying k
        ! by concentration(s)
        RFLUX = KVEC(I)
        KLOOP: DO K=1, NEREAC(I)
            RFLUX = RFLUX*Y(IDEREAC(I,K))/Y(NSTATE)
        END DO KLOOP
                WRITE(40,*) I, T, RFLUX/(THRESH*FLUXRC)
        ! loop over reaction products, adding RFLUX
        JLOOP: DO J=1, NEPROD(I)
            RATE(IDEPROD(I,J))=RATE(IDEPROD(I,J))+ RFLUX
        END DO JLOOP
    END DO ILOOP


    ! check if any of the edge species fluxes exceed
    ! the threshhold; if so, set edgeflag equal to
    ! the index of the first species found and exit
    ! the loop
    ! 5/7/08 gmagoon: added write statements for debugging purposes
!   OPEN (UNIT=20, FILE = 'debug.txt')
!   WRITE(20,*) FLUXRC 
        do i=1,nstate-1
         write(25,*) i, T, y(i)/y(nstate)
        end do
    FLOOP: DO I=1, ESPECIES
!       WRITE(20,*) I, RATE(I)
                WRITE(30,*) I, T, RATE(I)/(THRESH*FLUXRC)
        IF(RATE(I) .GE. THRESH*FLUXRC) THEN
           EDGEFLAG = I
!          EXIT FLOOP
        END IF
    END DO FLOOP


    DEALLOCATE(RATE)
END SUBROUTINE EDGEFLUX

! RCHAR calculates the characteristic flux (i.e. the 
! L2 norm of the core species fluxes), which it
! returns through the variable FLUXRC); the subroutine
! is called by EDGEFLUX; Y and YPRIME contain the 
! state variables and state variable derivatives,
! respectively; state vars. include the number of moles of
! each species, with the volume as the final state
! variable; NSTATE indicates the number of state
! variables (equal to the number of core species
! plus one)
SUBROUTINE RCHAR(FLUXRC, Y, YPRIME, NSTATE)
       IMPLICIT NONE 
    INTEGER NSTATE, I
    DOUBLE PRECISION SSF, FLUXRC, Y(NSTATE), YPRIME(NSTATE)
    ! compute the sum of squared fluxes
    SSF=0.0
    DO I=1, NSTATE-1
    ! add (dCi/dt)^2 with dCi/dt computed based on
      ! quotient rule...dCi/dt=d(Ni/V)/dt
    ! =(V*dNi/dt-Ni*dV/dt)/V^2
        SSF=SSF+((Y(NSTATE)*YPRIME(I)-Y(I)*YPRIME(NSTATE)) &
       &                        /(Y(NSTATE)**2))**2
    END DO
    ! compute the square root, corresponding to
      ! L2 norm
    FLUXRC = SSF**0.5
END SUBROUTINE RCHAR
