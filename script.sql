create table Company
(
    CompanyID   int identity
        primary key,
    Address     varchar(255) not null,
    CompanyName varchar(255) not null,
    Phone       varchar(127) not null,
    [e-mail]    varchar(63)  not null
        check ([e-mail] like '_%@_%._%')
)
go

create table Conference
(
    ConferenceID int identity
        primary key,
    BeginDate    date         not null,
    EndDate      date         not null,
    Name         varchar(255) not null,
    constraint CHK_DATE
        check (datediff(day, [BeginDate], [EndDate]) >= 0)
)
go

create table ConferenceReservation
(
    ConferenceReservationID int identity
        primary key,
    CompanyID               int  not null
        constraint FKConference595044
            references Company,
    ConferenceID            int  not null
        constraint FKConference392607
            references Conference
            on delete cascade,
    ReservationDate         date not null
)
go

create table Days
(
    DayID          int identity
        primary key,
    ConferenceID   int           not null
        constraint FKDays575639
            references Conference
            on delete cascade,
    NumberOfPlaces int default 0 not null
        check ([NumberOfPlaces] > 0),
    DayDate        date          not null,
    unique (ConferenceID, DayDate)
)
go

create table DayReservation
(
    DayReservationID        int identity
        primary key,
    ConferenceReservationID int not null
        constraint FKDayReserva734297
            references ConferenceReservation,
    DayID                   int not null
        constraint FKDayReserva96605
            references Days
            on delete cascade,
    NumberOfPlaces          int not null
        check ([NumberOfPlaces] > 0),
    unique (ConferenceReservationID, DayID)
)
go

create TRIGGER CorrectDayBooking
    on DayReservation
    after insert as
begin
    set nocount on;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
                     inner join Days AS d
                                ON d.DayID = i.DayID
                     inner join Conference AS c1 ON c1.ConferenceID = d.ConferenceID
                     inner join ConferenceReservation AS r
                                ON i.ConferenceReservationID = r.ConferenceReservationID
                     inner join Conference AS c2 ON c2.ConferenceID = r.ConferenceID
            WHERE c1.ConferenceID != c2.ConferenceID
        )
        BEGIN
            ; THROW 50001 , 'Rezerwowany dzień nie pochodzi z zarezerwowanej konferencji' ,1
        END
end
go

create trigger NoMoreDayBookingAfterPayment
    on DayReservation
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS
        (
            select *
            from inserted as i
                     inner join Payment as p on i.ConferenceReservationID = p.ConferenceReservationID
            where p.PaymentDay is not null
        )
        begin
            ; THROW 50001 , 'Rezerwacja została już opłacona, nie można dokonywać kolejnych rezerwacji miejsc na dzień. ' ,1
        end
end
go

CREATE TRIGGER NoPlaceForDay
    on DayReservation
    after insert as
begin
    set nocount on;
    IF EXISTS
        (
            SELECT *
            from inserted as i
            where dbo.DayFreePlaces(i.DayID) < 0
        )
        BEGIN
            ; THROW 50001 , 'Nie ma wystarczającej ilosci wolnych miejsc w tym dniu' ,1
        END
end
go

CREATE TRIGGER CorrectDayCapacity
    on dbo.Days
    AFTER INSERT , UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
            WHERE dbo.DayFreePlaces(i.DayID) < 0
        )
        BEGIN
            ; THROW 50001 , 'Na ten dzień konferencji zapisało się już więcej użydkowników niż podana nowa liczba miejsc' ,1
        END
END
go

create table Participant
(
    ParticipantID int identity
        primary key,
    CompanyID     int         not null
        constraint FKParticipan762161
            references Company,
    FirstName     varchar(63) not null,
    LastName      varchar(63) not null,
    StudentCard   int
        check ([StudentCard] >= 0)
)
go

create table ParticipantsForDay
(
    ParticipantsForDayID int identity
        primary key,
    ParticipantID        int not null
        constraint FKParticipan37239
            references Participant,
    DayReservationID     int not null
        constraint FKParticipan276571
            references DayReservation
            on delete cascade,
    unique (ParticipantID, DayReservationID)
)
go

create trigger CanStudentBeAdded
    on ParticipantsForDay
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS
        (
            select *
            from inserted as i
                     inner join Participant as p on i.ParticipantID = p.ParticipantID
                     inner join DayReservation as dr on dr.DayReservationID = i.DayReservationID
                     inner join Payment as pay on pay.ConferenceReservationID = dr.ConferenceReservationID
            where p.StudentCard is not null
              and pay.PaymentDay is not null
        )
        begin
            ;
            THROW 50001 , 'Rezerwacja została już opłacona, żeby dodać studenta i otrzymać za niego zniżkę trzeba dokonać tego przy dokonaniu rezerwacji i przed dokonaniem płatności.
                         Jeżeli nie zrobi się tego w odpowiednim terminie, student może uczestniczyć w konferencji ale jako zwykła osoba. ' ,1
        end
end
go

CREATE trigger CorrectPartcipantCompany
    on ParticipantsForDay
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS
        (
            select *
            from inserted as i
                     inner join dbo.Participant as p on i.ParticipantID = p.ParticipantID
                     inner join Company as c1 on p.CompanyID = c1.CompanyID
                     inner join DayReservation as dr on dr.DayReservationID = i.DayReservationID
                     inner join ConferenceReservation as cr on dr.ConferenceReservationID = cr.ConferenceReservationID
                     inner join Company as c2 on cr.CompanyID = c2.CompanyID
            where c1.CompanyID != c2.CompanyID
        )
        begin
            ; THROW 50001 , 'Uczestnik nie jest pracownikiem firmy, która wykonała rezerwacje.' ,1
        end
end
go

CREATE trigger NoPlaceForParticipantInDay
    on ParticipantsForDay
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
            WHERE ((select NumberOfPlaces
                    from DayReservation
                    where DayReservation.DayReservationID = i.DayReservationID)
                < (select count(*) from ParticipantsForDay as p where p.DayReservationID = i.DayReservationID))
        )
        BEGIN
            ; THROW 50001 , 'Nie ma miejsca dla kolejnego uczestnika na ten dzień konferencji.' ,1
        END
end
go

create table Payment
(
    PaymentID               int identity
        primary key,
    ConferenceReservationID int  not null
        unique
        constraint FKPayment880455
            references ConferenceReservation
            on delete cascade,
    PaymentDay              date not null
)
go

create table PriceThreshold
(
    PriceThresholdID int identity
        primary key,
    ConferenceID     int  not null
        constraint FKPriceTresh540978
            references Conference
            on delete cascade,
    beginDate        date not null,
    Price            int  not null
        check ([Price] >= 0),
    unique (ConferenceID, beginDate)
)
go

CREATE TRIGGER CorrectPriceThresholdDate
    ON PriceThreshold
    AFTER INSERT AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
                     inner join Conference AS c ON c.ConferenceID = i.ConferenceID
            WHERE i.beginDate > c.BeginDate
        )
        BEGIN
            ; THROW 50001 , 'Próg Cenowy rozpoczyna się po rozpoczęciu konferencji. ' ,1
        END
END
go

create table Workshops
(
    WorkshopID     int identity
        primary key,
    Name           varchar(255) not null,
    DayID          int          not null
        constraint FKWorkshops622279
            references Days
            on delete cascade,
    StartTime      time         not null,
    EndTime        time         not null,
    NumberOfPlaces int          not null
        check ([NumberOfPlaces] > 0),
    Price          int
        check ([Price] >= 0),
    constraint CHK_TIME
        check ([StartTime] < [EndTime])
)
go

CREATE TRIGGER CorrectWorkshopCapacity
    on dbo.Workshops
    AFTER INSERT , UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
            WHERE dbo.WorkshopFreePlaces(i.WorkshopID) < 0
        )
        BEGIN
            ; THROW 50001 , 'Na warsztat zapisało się już więcej użydkowników niż podana nowa liczba miejsc' ,1
        END
END
go

create table WorkshopsReservation
(
    WorkshopsReservationID int identity
        primary key,
    DayReservationID       int not null
        constraint FKWorkshopsR574165
            references DayReservation,
    WorkshopID             int not null
        constraint FKWorkshopsR114786
            references Workshops
            on delete cascade,
    NumberOfPlaces         int not null
        check ([NumberOfPlaces] > 0),
    unique (WorkshopID, DayReservationID)
)
go

create table WorkshopsParticipants
(
    WorkshopsParticipantsID int identity
        primary key,
    ParticipantForDayID     int not null
        constraint FKWorkshopsP170974
            references ParticipantsForDay
            on delete cascade,
    WorkShopReservationID   int not null
        constraint FKWorkshopsP739489
            references WorkshopsReservation,
    unique (ParticipantForDayID, WorkShopReservationID)
)
go

CREATE trigger CheckWorkshopCollision
    on WorkshopsParticipants
    after insert as
begin
    SET NOCOUNT ON;

    IF EXISTS(
            select *
            from inserted as i
                     inner join WorkshopsReservation as wr
                                on i.WorkShopReservationID = wr.WorkshopsReservationID
                     inner join WorkshopsParticipants as wp on i.ParticipantForDayID = wp.ParticipantForDayID
                     inner join WorkshopsReservation as wr2 on wp.WorkShopReservationID = wr2.WorkshopsReservationID
            where dbo.WorkshopCollision(wr2.WorkshopID, wr.WorkshopID) = 1
              and wr2.WorkshopID != wr.WorkshopID
        )
        BEGIN
            ; THROW 50001, 'Uzytkownik jest juz zapisny na inny warsztat w tym samym czasie', 1
        end
end
go

CREATE trigger CorrectWorkshopParticipantDay
    on WorkshopsParticipants
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS(
            SELECT *
            from inserted as i
                     inner join dbo.WorkshopsReservation as wr on i.WorkShopReservationID = wr.WorkshopsReservationID
                     inner join ParticipantsForDay as pd on i.ParticipantForDayID = pd.ParticipantsForDayID
            where pd.DayReservationID != wr.DayReservationID
        )
        BEGIN
            ; THROW 50001 , 'Uzydkownik nie jest zapisany na dzien, którego dotyczy rezerwacja warsztatu' ,1
        END
end
go

CREATE trigger NoPlaceForParticipantInWorkshop
    on WorkshopsParticipants
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
            WHERE ((select NumberOfPlaces
                    from WorkshopsReservation
                    where WorkshopsReservation.WorkshopsReservationID = i.WorkShopReservationID)
                < (select count(*)
                   from WorkshopsParticipants as p
                   where p.WorkShopReservationID = i.WorkShopReservationID))
        )
        BEGIN
            ; THROW 50001 , 'Nie ma miejsca dla kolejnego uczestnika na ten warsztat.' ,1
        END
end
go

create trigger CorrectWorkshopBooking
    on WorkshopsReservation
    after insert as
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
                     inner join Workshops as w on i.WorkshopID = w.WorkshopID
                     inner join Days AS d1
                                ON d1.DayID = w.DayID
                     inner join DayReservation as r on r.DayReservationID = i.DayReservationID
                     inner join Days as d2 on d2.DayID = r.DayID
            WHERE d1.DayID != d2.DayID
        )
        BEGIN
            ; THROW 50001 , 'Warsztat odbywa sie w dniu, którego nie dotyczy podana rezerwacja dnia' ,1
        END
END
go

CREATE TRIGGER LessPlaceInWorkshopThanDay
    on WorkshopsReservation
    AFTER INSERT , UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS
        (
            SELECT *
            FROM inserted AS i
                     inner join DayReservation as r on i.DayReservationID = r.DayReservationID
            WHERE i.NumberOfPlaces > r.NumberOfPlaces
        )
        BEGIN
            ; THROW 50001 , 'Nie możesz zarezerwować więcej miejsc na warsztat niż na dzień!' ,1
        END
END
go

create trigger NoMoreWorkshopBookingAfterPayment
    on WorkshopsReservation
    after insert as
begin
    SET NOCOUNT ON;
    IF EXISTS
        (
            select *
            from inserted as i
                     inner join DayReservation as dr on dr.DayReservationID = i.DayReservationID
                     inner join Payment as p on dr.ConferenceReservationID = p.ConferenceReservationID
            where p.PaymentDay is not null
        )
        begin
            ; THROW 50001 , 'Rezerwacja została już opłacona, nie można dokonywać kolejnych rezerwacji miejsc na warsztaty. ' ,1
        end
end
go

CREATE TRIGGER NoPlaceForWorkshop
    on WorkshopsReservation
    after insert as
begin
    set nocount on;
    IF EXISTS
        (
            SELECT *
            from inserted as i
            where dbo.WorkshopFreePlaces(i.WorkshopID) < 0
        )
        BEGIN
            ; THROW 50001 , 'Nie ma wystarczającej ilosci wolnych miejsc na warsztat w tym dniu' ,1
        END
end
go

create table sysdiagrams
(
    name         sysname not null,
    principal_id int     not null,
    diagram_id   int identity
        primary key,
    version      int,
    definition   varbinary(max),
    constraint UK_principal_name
        unique (principal_id, name)
)
go

CREATE VIEW AmountToPayForConferenceReservation AS
SELECT Conference.Name,
       CompanyName,
       Address,
       Phone,
       [e-mail],
       dbo.CalculateAmountToPay(cr.ConferenceReservationID) as toPay
from Conference
         join ConferenceReservation CR on Conference.ConferenceID = CR.ConferenceID
         join Company C on CR.CompanyID = C.CompanyID
go

CREATE VIEW ConferenceDayParticipants AS
SELECT C3.Name,
       d.DayDate,
       p2.FirstName,
       p2.LastName,
       p2.StudentCard,
       c4.Address,
       C4.CompanyName,
       C4.Phone,
       C4.[e-mail]
from Days d
         join Conference C3 on d.ConferenceID = C3.ConferenceID
         JOIN DayReservation dr on d.DayID = dr.DayID
         JOIN ParticipantsForDay pfr on pfr.DayReservationID = dr.DayReservationID
         JOIN Participant P2 on pfr.ParticipantID = P2.ParticipantID
         JOIN Company C4 on P2.CompanyID = C4.CompanyID
go

create view ConferenceIncome as
select c.ConferenceID,
       c.BeginDate,
       c.EndDate,
       c.Name,
       sum(dbo.CalculateAmountToPay(cr.ConferenceReservationID)) as ConferenceIncome
from Conference as c
         left outer join ConferenceReservation as cr on c.ConferenceID = cr.ConferenceID
group by c.ConferenceID, c.BeginDate, c.EndDate, c.Name
go

create view ConferencePopularity as
select c.ConferenceID, c.BeginDate, c.EndDate, c.Name, dbo.ConferenceAttendance(c.ConferenceID) as Attendance
from Conference as c
go

CREATE VIEW ConferenceWorkshopParticipants AS
SELECT C3.Name,
       w.Name as WorkshopName,
       d.DayDate,
       w.StartTime,
       w.EndTime,
       w.NumberOfPlaces,
       w.Price,
       p2.FirstName,
       p2.LastName,
       p2.StudentCard,
       c4.Address,
       C4.CompanyName,
       C4.Phone,
       C4.[e-mail]
from Days d
         join Conference C3 on d.ConferenceID = C3.ConferenceID
         JOIN Workshops W on d.DayID = W.DayID
         JOIN WorkshopsReservation wr on wr.WorkshopID = w.WorkshopID
         join WorkshopsParticipants wp on wp.WorkShopReservationID = wr.WorkshopsReservationID
         JOIN ParticipantsForDay pfr on pfr.ParticipantsForDayID = wp.ParticipantForDayID
         JOIN Participant P2 on pfr.ParticipantID = P2.ParticipantID
         JOIN Company C4 on P2.CompanyID = C4.CompanyID
go

create view CustomersWithNotFilledReservation as
select c.CompanyID, c.Address, c.CompanyName, c.Phone, c.[e-mail], cr.ConferenceReservationID
from Company as c
         inner join ConferenceReservation as cr on c.CompanyID = cr.CompanyID
where cr.ConferenceReservationID in
      (select dr.ConferenceReservationID
       from DayReservation as dr
                left outer join ParticipantsForDay as p on p.DayReservationID = dr.DayReservationID
       group by dr.ConferenceReservationID, dr.DayReservationID, dr.NumberOfPlaces
       having dr.NumberOfPlaces > count(p.ParticipantsForDayID)
      )
   or cr.ConferenceReservationID in
      (
          select dr2.ConferenceReservationID
          from DayReservation as dr2
                   inner join WorkshopsReservation as wr on dr2.DayReservationID = wr.DayReservationID
                   left outer join WorkshopsParticipants as wp on wp.WorkShopReservationID = wr.WorkshopsReservationID
          group by dr2.ConferenceReservationID, wr.WorkshopsReservationID, wr.NumberOfPlaces
          having wr.NumberOfPlaces > count(wp.WorkshopsParticipantsID)
      )
go

CREATE VIEW FreePlacesPerConferenceDay AS
SELECT D.DayDate, Name, (dbo.DayFreePlaces(D.DayID)) AS freeplaces
from Days d
         join Conference C4 on d.ConferenceID = C4.ConferenceID
go

CREATE VIEW FreePlacesPerConferenceWorkshop AS
SELECT w.Name, w.StartTime, w.EndTime, d2.DayDate, (dbo.WorkshopFreePlaces(w.WorkshopID)) as freePlaces
from Workshops w
         JOIN Days D2 on w.DayID = D2.DayID
go

CREATE VIEW ManyParticipantsCompanies AS
SELECT CompanyName, Address, Phone, [e-mail], count(*) as employees
from Company c
         join Participant P on c.CompanyID = P.CompanyID
GROUP BY CompanyName, Address, Phone, [e-mail]
HAVING count(*) > 1
go

CREATE VIEW MostActiveCustomers AS
SELECT C.Address, C.CompanyName, c.Phone, C.[e-mail], count(*) as conferences
FROM Company C
         JOIN ConferenceReservation CR3 on C.CompanyID = CR3.CompanyID
GROUP BY cr3.CompanyID, C.Address, C.CompanyName, c.Phone, C.[e-mail]
go

CREATE VIEW MostActiveParticipants AS
SELECT u.FirstName,
       u.LastName,
       u.StudentCard,
       c3.[e-mail],
       c3.Phone,
       c3.Address,
       c3.CompanyName,
       count(*) as Conferences
from Participant u
         JOIN Company C3 on u.CompanyID = C3.CompanyID
         JOIN ConferenceReservation CR on C3.CompanyID = CR.CompanyID
where u.ParticipantID in (select pd.ParticipantID
                          from ParticipantsForDay as pd
                                   inner join DayReservation DR on pd.DayReservationID = DR.DayReservationID
                                   inner join ConferenceReservation C
                                              on DR.ConferenceReservationID = C.ConferenceReservationID
                          where C.ConferenceReservationID = CR.ConferenceReservationID)
group by u.ParticipantID, u.FirstName, u.LastName, u.StudentCard, c3.[e-mail], c3.Phone, c3.Address, c3.CompanyName,
         c3.CompanyID
go

CREATE VIEW NotStudentsParticipants AS
SELECT FirstName, LastName, StudentCard, CompanyName, Address, Phone, [e-mail]
from Company c
         join Participant P on c.CompanyID = P.CompanyID
where StudentCard is null
go

CREATE VIEW OneParticipantCompanies AS
SELECT CompanyName, Address, Phone, [e-mail], FirstName, LastName, StudentCard
from Company c
         join Participant P on c.CompanyID = P.CompanyID
where c.CompanyID in (SELECT Company.CompanyID
                      from Company
                               join Participant P on Company.CompanyID = P.CompanyID
                      group by p.CompanyID, Company.CompanyID
                      having count(*) = 1)
go

create view PaidReservations as
select c.ConferenceReservationID,
       c.ReservationDate,
       com.CompanyName,
       com.Address,
       com.Phone,
       com.[e-mail]
from ConferenceReservation as c
         inner join Company as com on c.CompanyID = com.CompanyID
         left outer join Payment as p on p.ConferenceReservationID = c.ConferenceReservationID
where p.PaymentID is not null
go

CREATE VIEW ParticipantsWithCompanies AS
SELECT FirstName, LastName, StudentCard, CompanyName, Address, Phone, [e-mail]
from Company c
         join Participant P on c.CompanyID = P.CompanyID
go

CREATE VIEW StudentsParticipants AS
SELECT FirstName, LastName, StudentCard, CompanyName, Address, Phone, [e-mail]
from Company c
         join Participant P on c.CompanyID = P.CompanyID
where StudentCard is not null
go

create view UnpaidReservations as
select c.ConferenceReservationID,
       c.ReservationDate,
       com.CompanyName,
       com.Address,
       com.Phone,
       com.[e-mail],
       DATEDIFF(day, c.ReservationDate, getdate()) as DaysFromReservationsDate
from ConferenceReservation as c
         inner join Company as com on c.CompanyID = com.CompanyID
         left outer join Payment as p on p.ConferenceReservationID = c.ConferenceReservationID
where p.PaymentID is null
go

CREATE view WorkshopsPopularity as
select w.WorkshopID,
       w.Name,
       w.DayID,
       w.StartTime,
       w.EndTime,
       w.NumberOfPlaces,
       w.Price,
       coalesce(sum(wr.NumberOfPlaces), 0) as NumberOfParticipants
from Workshops as w
         left outer join WorkshopsReservation as wr on w.WorkshopID = wr.WorkshopID
group by w.WorkshopID, w.WorkshopID, w.Name, w.DayID, w.StartTime, w.EndTime, w.NumberOfPlaces, w.Price
go

CREATE PROCEDURE AddCompany @Address varchar(255), @CompanyName varchar(255), @Phone varchar(127), @email varchar(63) AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        INSERT INTO Company
        (Address,
         CompanyName,
         Phone,
         [e-mail])
        VALUES (@Address,
                @CompanyName,
                @Phone,
                @email)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot add Comapny . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

create procedure AddConference @name varchar(255), @beginDate date, @endDate date as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF (@beginDate < GETDATE())
            BEGIN
                ;
                THROW 52000,
                    'Konferencje nie moga byc tworzone w przeszlosci', 1;
            END
        IF (@beginDate > @endDate)
            BEGIN
                ;
                THROW 52000,
                    'Data rozpoczęcia konferencji musi byc przed jej zakończeniem', 1;
            END
        INSERT INTO Conference(begindate, enddate, name) VALUES (@beginDate, @endDate, @name)
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2048) =
                'Bład stworzenia konferencji:' +
                CHAR(13) + CHAR(10) + ERROR_MESSAGE();
        THROW 52000,@msg, 1;
    END CATCH
END
go

create procedure AddDay @ConferenceId int, @NumberOfPlaces int, @DayDate date as
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Conference
                WHERE ConferenceID = @ConferenceID
            )
            BEGIN
                ; THROW 52000 , 'Konferencja nie istnieje' ,1
            END
        INSERT INTO Days
        (ConferenceID, NumberOfPlaces, DayDate)
        VALUES (@ConferenceId,
                @NumberOfPlaces,
                @DayDate)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot add conference day. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

create procedure AddParticipant @CompanyID int, @FirstName varchar(63), @LastName varchar(63), @StudentCard int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Company
                WHERE CompanyID = @CompanyID
            )
            BEGIN
                ; THROW 52000 , 'Firma nie istnieje' ,1
            END
        INSERT INTO Participant(CompanyID, FirstName, LastName, StudentCard)
        VALUES (@CompanyID, @FirstName, @LastName, @StudentCard)
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2048) =
                'Bład stworzenia uczestnika:' +
                CHAR(13) + CHAR(10) + ERROR_MESSAGE();
        THROW 52000,@msg, 1;
    END CATCH
END
go

CREATE PROCEDURE AddParticipantToDay @ParticipantID int, @DayReservationID int as
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM DayReservation
                WHERE DayReservationID = @DayReservationID
            )
            BEGIN
                ; THROW 52000 , 'Nie istnieje podana rezerwacja dnia. ' ,1
            END
        IF NOT EXISTS
            (
                SELECT *
                FROM Participant
                WHERE ParticipantID = @ParticipantID
            )
            BEGIN
                ; THROW 52000 , 'Nie istnieje podany uczestnik. ' ,1
            END
        INSERT INTO ParticipantsForDay
        (DayReservationID,
         ParticipantID)
        VALUES (@DayReservationID,
                @ParticipantID)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot add participant to day . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE procedure AddParticipantToWorkshop @ParticipantsForDayID int, @WorkShopReservationId int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM ParticipantsForDay
                WHERE ParticipantsForDayID = @ParticipantsForDayID
            )
            BEGIN
                ; THROW 52000 , 'Uzytkownik nie jest zapisany na żaden dzien rezerwacji' ,1
            END
        IF NOT EXISTS
            (
                SELECT *
                FROM WorkshopsReservation
                WHERE WorkshopsReservationID = @WorkShopReservationId
            )
            BEGIN
                ; THROW 52000 , 'Podana rezewacja warsztatu nie istnieje' ,1
            END
        INSERT INTO WorkshopsParticipants(ParticipantForDayID, WorkShopReservationID)
        VALUES (@ParticipantsForDayID, @WorkShopReservationID)
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2048) =
                'Bład dodania uczestnika do warsztatu:' +
                ERROR_MESSAGE();
        THROW 52000,@msg, 1;
    END CATCH
END
go

CREATE procedure AddPayment @ConferenceReservationID int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @Date date = getDate();
        IF NOT EXISTS
            (
                SELECT *
                FROM ConferenceReservation
                WHERE ConferenceReservationID = @ConferenceReservationID
            )
            BEGIN
                ; THROW 52000 , 'Rezerwacja nie istnieje' ,1
            END
        INSERT INTO Payment(ConferenceReservationID, PaymentDay) VALUES (@ConferenceReservationID, @Date)
    END TRY
    BEGIN CATCH
        DECLARE @msg NVARCHAR(2048) =
                'Bład stworzenia płatności:' +
                CHAR(13) + CHAR(10) + ERROR_MESSAGE();
        THROW 52000,@msg, 1;
    END CATCH
END
go

CREATE PROCEDURE AddPriceThreshold @ConferenceID int, @beginDate date, @Price int AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Conference
                WHERE ConferenceID = @ConferenceID
            )
            BEGIN
                ; THROW 52000 , 'Nie istnieje podana konferencja.' ,1
            END
        INSERT INTO PriceThreshold
        (ConferenceID,
         beginDate,
         Price)
        VALUES (@ConferenceID,
                @beginDate,
                @Price)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot add PriceThreshold . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

CREATE PROCEDURE AddWorkshop @DayID int, @Name nvarchar(255), @NumberOfPlaces int, @StartHour time(7), @EndHour time(7),
                             @Price money AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Days
                WHERE DayID = @DayID
            )
            BEGIN
                ; THROW 52000 , 'Nie istnieje podany dzień konferencji.' ,1
            END
        INSERT INTO Workshops
        (DayID,
         Name,
         NumberOfPlaces,
         StartTime,
         EndTime,
         Price)
        VALUES (@DayID,
                @Name,
                @NumberOfPlaces,
                @StartHour,
                @EndHour,
                @Price)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot add workshop . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

CREATE PROCEDURE BookConference @CompanyID int, @ConferenceID int AS
BEGIN
    SET NOCOUNT ON
    DECLARE @Date date = GETDATE()
    Declare @ConferenceDate date =
        (
            select BeginDate
            from Conference
            where ConferenceID = @ConferenceID
        )
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Conference
                WHERE ConferenceID = @ConferenceID
            )
            BEGIN
                ; THROW 52000 , 'Konferencja nie istnieje.',1
            END
        IF NOT EXISTS
            (
                SELECT *
                FROM Company
                WHERE CompanyID = @CompanyID
            )
            BEGIN
                ; THROW 52000 , 'Firma nie istnieje.' ,1
            END
        IF @ConferenceDate < (DATEADD(day, 14, @Date))
            BEGIN
                ; THROW 52000 , 'Nie mozna zarezerwować konferencji na mniej niz 14 dni przed jej rozpoczęciem' ,1
            END
        INSERT INTO ConferenceReservation
        (CompanyID,
         ConferenceID,
         ReservationDate)
        VALUES (@CompanyID,
                @ConferenceID,
                @Date)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot book conference . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE PROCEDURE BookDay @ConferenceReservationID int, @DayID int, @NumberOfPlaces int AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM ConferenceReservation
                WHERE ConferenceReservationID = @ConferenceReservationID
            )
            BEGIN
                ; THROW 52000 , 'Rezerwacja konferencji nie istnieje.' ,1
            END
        IF NOT EXISTS
            (
                SELECT *
                FROM Days
                WHERE DayID = @DayID
            )
            BEGIN
                ; THROW 52000 , 'Dzień nie istnieje.' ,1
            END
        INSERT INTO DayReservation
        (DayID,
         ConferenceReservationID,
         NumberOfPlaces)
        VALUES (@DayID,
                @ConferenceReservationID,
                @NumberOfPlaces)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot book conference day. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE PROCEDURE BookWorkshop @DayReservationID int, @WorkshopID int, @NumberOfPlaces int as
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Workshops
                WHERE WorkshopID = @WorkshopID
            )
            BEGIN
                ; THROW 52000 , 'Podany warsztat nie istnieje.' ,1
            END
        IF NOT EXISTS
            (
                SELECT *
                FROM DayReservation
                WHERE DayReservationID = @DayReservationID
            )
            BEGIN
                ; THROW 52000 , 'Podana rezerwacja dnia nie istnieje.' ,1
            END
        INSERT INTO WorkshopsReservation
        (DayReservationID,
         WorkshopID,
         NumberOfPlaces)
        VALUES (@DayReservationID,
                @WorkshopID,
                @NumberOfPlaces)
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot book workshop . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE function CalculateAmountToPay(@ConferenceReservationID int) RETURNS FLOAT as
begin
    DECLARE @Discount int = 0.4
    DECLARE @PricePerPersonPerDay int =
        (
            select
            top 1
            pd.Price
            from PriceThreshold as pd
                     inner join ConferenceReservation as cr on cr.ConferenceID = pd.ConferenceID
            where cr.ConferenceReservationID = @ConferenceReservationID
              and pd.beginDate < GETDATE()
            ORDER BY pd.beginDate DESC
        )
    return (
            (select coalesce(sum(priceForDay), 0)
             from (
                      select sum(dbo.CountStudentsNumber(dr.DayReservationID) * @PricePerPersonPerDay * @Discount +
                                 (dr.NumberOfPlaces - dbo.CountStudentsNumber(dr.DayReservationID)) *
                                 @PricePerPersonPerDay) as priceForDay
                      from DayReservation as dr
                      where dr.ConferenceReservationID = @ConferenceReservationID
                      group by dr.DayReservationID, dr.NumberOfPlaces) as dayPrize)
            +
            (select coalesce(sum(pricePerWorkshop), 0)
             from (
                      select sum(w.Price * wr.NumberOfPlaces) as pricePerWorkshop
                      from Workshops as w
                               inner join WorkshopsReservation as wr on wr.WorkshopID = w.WorkshopID
                               inner join DayReservation as dr on wr.DayReservationID = dr.DayReservationID
                      where dr.ConferenceReservationID = @ConferenceReservationID
                      group by w.WorkshopID, w.Price, wr.NumberOfPlaces
                  ) as workshopPrice)
        )
end
go

CREATE PROCEDURE CancelConferenceReservation @ID int AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM ConferenceReservation
                WHERE ConferenceReservationID = @ID
            )
            BEGIN
                ; THROW 52000 , 'Podana rezerwacja konferencji nie istnieje .' ,1
            END
        DELETE WorkshopsParticipants
        where WorkShopReservationID in (select wr.WorkshopsReservationID
                                        from WorkshopsReservation as wr
                                        where wr.DayReservationID in (select dr.DayReservationID
                                                                      from DayReservation as dr
                                                                      where dr.ConferenceReservationID = @ID))
        DELETE WorkshopsReservation
        where DayReservationID in
              (select dr.DayReservationID from DayReservation as dr where dr.ConferenceReservationID = @ID)
        DELETE DayReservation where ConferenceReservationID = @ID
        DELETE ConferenceReservation where ConferenceReservationID = @ID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot cancel conference booking . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE PROCEDURE CancelDayReservation @DayReservationID int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM DayReservation
                WHERE DayReservationID = @DayReservationID
            )
            BEGIN
                ; THROW 52000 , 'Rezerwacja dnia nie istnieje.' ,1
            END
        DELETE WorkshopsParticipants
        where WorkShopReservationID in (select wr.WorkshopsReservationID
                                        from WorkshopsReservation as wr
                                        where wr.DayReservationID = @DayReservationID)
        DELETE WorkshopsReservation where DayReservationID = @DayReservationID
        DELETE DayReservation where DayReservationID = @DayReservationID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot cancel Day Reservation. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE PROCEDURE CancelUnpaidOnTimeReservations as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @CurrentID INT = 0
        -- Iterate over all customers
        WHILE (1 = 1)
            BEGIN
                -- Get next customerId
                SELECT
                TOP 1
                @CurrentID = c.ConferenceReservationID
                FROM ConferenceReservation as c
                WHERE c.ConferenceReservationID > @CurrentID
                ORDER BY c.ConferenceReservationID
                -- Exit loop if no more customers
                IF @@ROWCOUNT = 0 BREAK;
                -- call your sproc
                if @CurrentID in
                   (
                       SELECT cr.ConferenceReservationID
                       FROM ConferenceReservation as cr
                                left outer join Payment as p on p.ConferenceReservationID = cr.ConferenceReservationID
                       where p.PaymentID is null
                         and DATEDIFF(day, cr.ReservationDate, getdate()) > 7
                   )
                    begin
                        EXEC CancelConferenceReservation @ID = @CurrentID
                    end
            END
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot cancel unpaid time reservations . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE PROCEDURE CancelWorkshopReservation @WorkshopReservationID int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM WorkshopsReservation
                WHERE WorkshopsReservationID = @WorkshopReservationID
            )
            BEGIN
                ; THROW 52000 , 'Rezerwacja warsztatu ie istnieje.' ,1
            END
        DELETE WorkshopsParticipants where WorkShopReservationID = @WorkshopReservationID
        DELETE WorkshopsReservation where WorkshopsReservationID = @WorkshopReservationID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot cancel Workshop Reservation. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE FUNCTION ConferenceAttendance(@ID int) RETURNS integer as
begin

    declare @ConferencePlaces integer =
                (select sum(Days.NumberOfPlaces) from Days where ConferenceID = @ID)
            - (dbo.ConferenceFreePlaces(@ID))
    return @ConferencePlaces;
end
go

CREATE FUNCTION ConferenceDays(@ID int)
    RETURNS TABLE
        AS
        RETURN
            (
                SELECT d.DayID, d.DayDate, d.NumberOfPlaces
                FROM Days AS d
                where d.ConferenceID = @ID
            )
go

CREATE FUNCTION ConferenceFreePlaces(@ID int) RETURNS integer as
begin

    declare @ConferencePlaces integer =
        (select sum(dbo.DayFreePlaces(DayID)) from Days where ConferenceID = @ID)

    return @ConferencePlaces;
end
go

create function CountStudentsNumber(@DayReservationID int) RETURNS INT as
begin
    return (select count(*)
            from ParticipantsForDay as pd
                     inner join Participant as p on pd.ParticipantID = p.ParticipantID
            where pd.DayReservationID = @DayReservationID
              and p.StudentCard is not null)
end
go

CREATE FUNCTION DayFreePlaces(@ID int) RETURNS integer as
begin

    declare @dayPlaces integer =
        (SELECT Days.NumberOfPlaces
         from Days
         where DayID = @ID)
    declare @reservPlaces integer =
        (SELECT sum(NumberOfPlaces)
         from DayReservation
         WHERE DayID = @ID
         group by DayID)
    IF @reservPlaces IS NULL
        begin
            return @dayPlaces
        end

    return @dayPlaces - @reservPlaces;
end
go

CREATE FUNCTION DayParticipantsList(@ID int)
    RETURNS TABLE AS
        RETURN
            (
                SELECT *
                from Participant
                where ParticipantID IN
                      (SELECT ParticipantID
                       FROM ParticipantsForDay
                       where DayReservationID in
                             (SELECT DayReservationID
                              from DayReservation
                              where DayID = @ID))
            )
go

CREATE FUNCTION DayWorkshops(@ID int)
    RETURNS TABLE as
        RETURN
            (
                SELECT w.WorkshopID, w.Name, w.StartTime, w.EndTime, w.NumberOfPlaces, w.Price
                from Workshops as w
                where w.DayID = @ID
            )
go

create function ParticipantDayList(@ParticipantID int, @ConferenceID int)
    RETURNS TABLE as
        RETURN
            (
                select d.DayID, d.DayDate
                from Days as d
                         inner join DayReservation as dr
                                    on dr.DayID = d.DayID
                         inner join ParticipantsForDay as p on p.DayReservationID = dr.DayReservationID
                where p.ParticipantID = @ParticipantID
                  and d.ConferenceID = @ConferenceID
            )
go

CREATE FUNCTION ParticipantWorkshopsList(@ID int)
    RETURNS TABLE AS
        RETURN
            (
                SELECT *
                from Workshops
                where WorkshopID IN
                      (SELECT WorkshopID
                       FROM WorkshopsReservation
                       where WorkshopsReservationID in
                             (SELECT WorkShopReservationID
                              from WorkshopsParticipants
                              where ParticipantForDayID in
                                    (SELECT ParticipantsForDayID from ParticipantsForDay where ParticipantID = @ID)))
            )
go

create procedure RemoveConference @id int as
BEGIN
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Conference
                WHERE ConferenceID = @id
            )
            BEGIN
                ; THROW 52000 , 'Konferencja nie istnieje',1
            END
        delete from Conference where ConferenceID = @id
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot delete price treshold . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

create procedure RemoveDay @DayID int as
BEGIN
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Days
                WHERE DayID = @DayID
            )
            BEGIN
                ; THROW 52000 , 'Dzień nie istnieje' ,1
            END
        DELETE Days
        WHERE DayID = @DayID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot delete day. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

CREATE PROCEDURE RemoveParticipantFromDay @ParticipantForDayID int as
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM ParticipantsForDay AS pd
                WHERE pd.ParticipantsForDayID = @ParticipantForDayID
            )
            BEGIN
                ; THROW 50001 , 'Uczestnik ie był zapisany na ten dzień.' ,1
            END
        DELETE
        FROM ParticipantsForDay
        WHERE ParticipantsForDayID = @ParticipantForDayID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot remove Participant from day . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE PROCEDURE RemoveParticipantFromWorkshop @WorkshopParticipantID int as
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM WorkshopsParticipants AS p
                WHERE p.WorkshopsParticipantsID = @WorkshopParticipantID
            )
            BEGIN
                ; THROW 50001 , 'Podany uczestnik nie istnieje',1
            END
        DELETE
        FROM WorkshopsParticipants
        WHERE WorkshopsParticipantsID = @WorkshopParticipantID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot remove Workshop participant . Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1;
    END CATCH
END
go

CREATE procedure RemovePriceThreshold @PriceThresholdID int as
BEGIN
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM PriceThreshold
                WHERE PriceThresholdID = @PriceThresholdID
            )
            BEGIN
                ; THROW 52000 , 'Próg cenowy  nie istnieje' ,1
            END
        DELETE PriceThreshold
        WHERE PriceThresholdID = @PriceThresholdID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot delete PriceThreshold. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

create procedure RemoveWorkshop @WorkshopID int as
BEGIN
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Workshops
                WHERE WorkshopID = @WorkshopID
            )
            BEGIN
                ; THROW 52000 , 'Warsztat nie istnieje' ,1
            END
        DELETE Workshops
        WHERE WorkshopID = @WorkshopID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot delete Workshop. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

create procedure UpdateConferenceDayCapacity @DayID int, @NewCapacity int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Days
                WHERE DayID = @DayID
            )
            BEGIN
                ; THROW 52000 , 'Podany dzien konferencji nie istnieje' ,1
            END
        UPDATE Days set NumberOfPlaces=@NewCapacity where DayID = @DayID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot Update Day Capacity. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

create procedure UpdateWorkshopCapacity @WorkshopID int, @NewCapacity int as
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS
            (
                SELECT *
                FROM Workshops
                WHERE WorkshopID = @WorkshopID
            )
            BEGIN
                ; THROW 52000 , 'Warsztat nie istnieje' ,1
            END
        UPDATE Workshops set NumberOfPlaces=@NewCapacity where WorkshopID = @WorkshopID
    END TRY
    BEGIN CATCH
        DECLARE @errorMsg nvarchar(2048)
            = 'Cannot Update Workshop Capacity. Error message : '
                + ERROR_MESSAGE();
        ;
        THROW 52000 , @errorMsg ,1
    END CATCH
END
go

create function WorkshopCollision(@ID1 int, @ID2 int) RETURNS Bit as
begin
    DECLARE @Start_1 time = (select StartTime from Workshops where WorkshopID = @ID1);
    DECLARE @End_1 time = (select EndTime from Workshops where WorkshopID = @ID1);
    DECLARE @Start_2 time = (select StartTime from Workshops where WorkshopID = @ID2);
    DECLARE @End_2 time = (select EndTime from Workshops where WorkshopID = @ID2);
    DECLARE @Day1 int = (select DayID from Workshops where WorkshopID = @ID1);
    DECLARE @Day2 int = (select DayID from Workshops where WorkshopID = @ID2);
    IF @Day1 != @Day2
        RETURN 0
    IF @Start_1 < @Start_2 AND @Start_2 < @End_1
        RETURN 1
    IF @Start_2 < @Start_1 AND @Start_1 < @End_2
        RETURN 1
    IF @Start_1 >= @Start_2 AND @End_2 >= @End_1
        RETURN 1
    IF @Start_2 >= @Start_1 AND @End_1 >= @End_2
        RETURN 1
    RETURN 0
END
go

CREATE FUNCTION WorkshopFreePlaces(@ID int) RETURNS integer as
begin

    declare @dayPlaces integer =
        (SELECT Workshops.NumberOfPlaces
         from Workshops
         where WorkshopID = @ID)
    declare @reservPlaces integer =
        (SELECT sum(NumberOfPlaces)
         from WorkshopsReservation
         WHERE WorkshopID = @ID
         group by WorkshopID)

    IF (@reservPlaces is NULL)
        begin
            return @dayPlaces;
        end

    return @dayPlaces - @reservPlaces;
end
go

CREATE FUNCTION WorkshopParticipantsList(@ID int)
    RETURNS TABLE AS
        RETURN
            (
                SELECT *
                from Participant
                where ParticipantID IN
                      (SELECT ParticipantID
                       FROM ParticipantsForDay
                       where ParticipantsForDayID in
                             (SELECT ParticipantForDayID
                              from WorkshopsParticipants
                              where WorkShopReservationID in
                                    (SELECT WorkshopsReservationID from WorkshopsReservation where WorkshopID = @ID)))
            )
go


CREATE FUNCTION dbo.fn_diagramobjects()
    RETURNS int
    WITH EXECUTE AS N'dbo'
AS
BEGIN
    declare @id_upgraddiagrams int
    declare @id_sysdiagrams int
    declare @id_helpdiagrams int
    declare @id_helpdiagramdefinition int
    declare @id_creatediagram int
    declare @id_renamediagram int
    declare @id_alterdiagram int
    declare @id_dropdiagram int
    declare @InstalledObjects int

    select @InstalledObjects = 0

    select @id_upgraddiagrams = object_id(N'dbo.sp_upgraddiagrams'),
           @id_sysdiagrams = object_id(N'dbo.sysdiagrams'),
           @id_helpdiagrams = object_id(N'dbo.sp_helpdiagrams'),
           @id_helpdiagramdefinition = object_id(N'dbo.sp_helpdiagramdefinition'),
           @id_creatediagram = object_id(N'dbo.sp_creatediagram'),
           @id_renamediagram = object_id(N'dbo.sp_renamediagram'),
           @id_alterdiagram = object_id(N'dbo.sp_alterdiagram'),
           @id_dropdiagram = object_id(N'dbo.sp_dropdiagram')

    if @id_upgraddiagrams is not null
        select @InstalledObjects = @InstalledObjects + 1
    if @id_sysdiagrams is not null
        select @InstalledObjects = @InstalledObjects + 2
    if @id_helpdiagrams is not null
        select @InstalledObjects = @InstalledObjects + 4
    if @id_helpdiagramdefinition is not null
        select @InstalledObjects = @InstalledObjects + 8
    if @id_creatediagram is not null
        select @InstalledObjects = @InstalledObjects + 16
    if @id_renamediagram is not null
        select @InstalledObjects = @InstalledObjects + 32
    if @id_alterdiagram is not null
        select @InstalledObjects = @InstalledObjects + 64
    if @id_dropdiagram is not null
        select @InstalledObjects = @InstalledObjects + 128

    return @InstalledObjects
END
go


CREATE PROCEDURE dbo.sp_alterdiagram(@diagramname sysname,
                                     @owner_id int = null,
                                     @version int,
                                     @definition varbinary(max))
    WITH EXECUTE AS 'dbo'
AS
BEGIN
    set nocount on

    declare @theId int
    declare @retval int
    declare @IsDbo int

    declare @UIDFound int
    declare @DiagId int
    declare @ShouldChangeUID int

    if (@diagramname is null)
        begin
            RAISERROR ('Invalid ARG', 16, 1)
            return -1
        end

    execute as caller;
    select @theId = DATABASE_PRINCIPAL_ID();
    select @IsDbo = IS_MEMBER(N'db_owner');
    if (@owner_id is null)
        select @owner_id = @theId;
    revert;

    select @ShouldChangeUID = 0
    select @DiagId = diagram_id, @UIDFound = principal_id
    from dbo.sysdiagrams
    where principal_id = @owner_id
      and name = @diagramname

    if (@DiagId IS NULL or (@IsDbo = 0 and @theId <> @UIDFound))
        begin
            RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1);
            return -3
        end

    if (@IsDbo <> 0)
        begin
            if (@UIDFound is null or USER_NAME(@UIDFound) is null) -- invalid principal_id
                begin
                    select @ShouldChangeUID = 1 ;
                end
        end

    -- update dds data			
    update dbo.sysdiagrams set definition = @definition where diagram_id = @DiagId;

    -- change owner
    if (@ShouldChangeUID = 1)
        update dbo.sysdiagrams set principal_id = @theId where diagram_id = @DiagId;

    -- update dds version
    if (@version is not null)
        update dbo.sysdiagrams set version = @version where diagram_id = @DiagId ;

    return 0
END
go


CREATE PROCEDURE dbo.sp_creatediagram(@diagramname sysname,
                                      @owner_id int = null,
                                      @version int,
                                      @definition varbinary(max))
    WITH EXECUTE AS 'dbo'
AS
BEGIN
    set nocount on

    declare @theId int
    declare @retval int
    declare @IsDbo int
    declare @userName sysname
    if (@version is null or @diagramname is null)
        begin
            RAISERROR (N'E_INVALIDARG', 16, 1);
            return -1
        end

    execute as caller;
    select @theId = DATABASE_PRINCIPAL_ID();
    select @IsDbo = IS_MEMBER(N'db_owner');
    revert;

    if @owner_id is null
        begin
            select @owner_id = @theId;
        end
    else
        begin
            if @theId <> @owner_id
                begin
                    if @IsDbo = 0
                        begin
                            RAISERROR (N'E_INVALIDARG', 16, 1);
                            return -1
                        end
                    select @theId = @owner_id
                end
        end
    -- next 2 line only for test, will be removed after define name unique
    if EXISTS(select diagram_id from dbo.sysdiagrams where principal_id = @theId and name = @diagramname)
        begin
            RAISERROR ('The name is already used.', 16, 1);
            return -2
        end

    insert into dbo.sysdiagrams(name, principal_id, version, definition)
    VALUES (@diagramname, @theId, @version, @definition);

    select @retval = @@IDENTITY
    return @retval
END
go


CREATE PROCEDURE dbo.sp_dropdiagram(@diagramname sysname,
                                    @owner_id int = null)
    WITH EXECUTE AS 'dbo'
AS
BEGIN
    set nocount on
    declare @theId int
    declare @IsDbo int

    declare @UIDFound int
    declare @DiagId int

    if (@diagramname is null)
        begin
            RAISERROR ('Invalid value', 16, 1);
            return -1
        end

    EXECUTE AS CALLER;
    select @theId = DATABASE_PRINCIPAL_ID();
    select @IsDbo = IS_MEMBER(N'db_owner');
    if (@owner_id is null)
        select @owner_id = @theId;
    REVERT;

    select @DiagId = diagram_id, @UIDFound = principal_id
    from dbo.sysdiagrams
    where principal_id = @owner_id
      and name = @diagramname
    if (@DiagId IS NULL or (@IsDbo = 0 and @UIDFound <> @theId))
        begin
            RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1)
            return -3
        end

    delete from dbo.sysdiagrams where diagram_id = @DiagId;

    return 0;
END
go


CREATE PROCEDURE dbo.sp_helpdiagramdefinition(@diagramname sysname,
                                              @owner_id int = null)
    WITH EXECUTE AS N'dbo'
AS
BEGIN
    set nocount on

    declare @theId int
    declare @IsDbo int
    declare @DiagId int
    declare @UIDFound int

    if (@diagramname is null)
        begin
            RAISERROR (N'E_INVALIDARG', 16, 1);
            return -1
        end

    execute as caller;
    select @theId = DATABASE_PRINCIPAL_ID();
    select @IsDbo = IS_MEMBER(N'db_owner');
    if (@owner_id is null)
        select @owner_id = @theId;
    revert;

    select @DiagId = diagram_id, @UIDFound = principal_id
    from dbo.sysdiagrams
    where principal_id = @owner_id
      and name = @diagramname;
    if (@DiagId IS NULL or (@IsDbo = 0 and @UIDFound <> @theId))
        begin
            RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1);
            return -3
        end

    select version, definition FROM dbo.sysdiagrams where diagram_id = @DiagId;
    return 0
END
go


CREATE PROCEDURE dbo.sp_helpdiagrams(@diagramname sysname = NULL,
                                     @owner_id int = NULL)
    WITH EXECUTE AS N'dbo'
AS
BEGIN
    DECLARE @user sysname
    DECLARE @dboLogin bit
    EXECUTE AS CALLER;
    SET @user = USER_NAME();
    SET @dboLogin = CONVERT(bit, IS_MEMBER('db_owner'));
    REVERT;
    SELECT [Database] = DB_NAME(),
           [Name]     = name,
           [ID]       = diagram_id,
           [Owner]    = USER_NAME(principal_id),
           [OwnerID]  = principal_id
    FROM sysdiagrams
    WHERE (@dboLogin = 1 OR USER_NAME(principal_id) = @user)
      AND (@diagramname IS NULL OR name = @diagramname)
      AND (@owner_id IS NULL OR principal_id = @owner_id)
    ORDER BY 4, 5, 1
END
go


CREATE PROCEDURE dbo.sp_renamediagram(@diagramname sysname,
                                      @owner_id int = null,
                                      @new_diagramname sysname)
    WITH EXECUTE AS 'dbo'
AS
BEGIN
    set nocount on
    declare @theId int
    declare @IsDbo int

    declare @UIDFound int
    declare @DiagId int
    declare @DiagIdTarg int
    declare @u_name sysname
    if ((@diagramname is null) or (@new_diagramname is null))
        begin
            RAISERROR ('Invalid value', 16, 1);
            return -1
        end

    EXECUTE AS CALLER;
    select @theId = DATABASE_PRINCIPAL_ID();
    select @IsDbo = IS_MEMBER(N'db_owner');
    if (@owner_id is null)
        select @owner_id = @theId;
    REVERT;

    select @u_name = USER_NAME(@owner_id)

    select @DiagId = diagram_id, @UIDFound = principal_id
    from dbo.sysdiagrams
    where principal_id = @owner_id
      and name = @diagramname
    if (@DiagId IS NULL or (@IsDbo = 0 and @UIDFound <> @theId))
        begin
            RAISERROR ('Diagram does not exist or you do not have permission.', 16, 1)
            return -3
        end

    -- if((@u_name is not null) and (@new_diagramname = @diagramname))	-- nothing will change
    --	return 0;

    if (@u_name is null)
        select @DiagIdTarg = diagram_id from dbo.sysdiagrams where principal_id = @theId and name = @new_diagramname
    else
        select @DiagIdTarg = diagram_id from dbo.sysdiagrams where principal_id = @owner_id and name = @new_diagramname

    if ((@DiagIdTarg is not null) and @DiagId <> @DiagIdTarg)
        begin
            RAISERROR ('The name is already used.', 16, 1);
            return -2
        end

    if (@u_name is null)
        update dbo.sysdiagrams set [name] = @new_diagramname, principal_id = @theId where diagram_id = @DiagId
    else
        update dbo.sysdiagrams set [name] = @new_diagramname where diagram_id = @DiagId
    return 0
END
go


CREATE PROCEDURE dbo.sp_upgraddiagrams
AS
BEGIN
    IF OBJECT_ID(N'dbo.sysdiagrams') IS NOT NULL
        return 0;

    CREATE TABLE dbo.sysdiagrams
    (
        name         sysname NOT NULL,
        principal_id int     NOT NULL, -- we may change it to varbinary(85)
        diagram_id   int PRIMARY KEY IDENTITY,
        version      int,

        definition   varbinary(max)
            CONSTRAINT UK_principal_name UNIQUE
                (
                 principal_id,
                 name
                    )
    );


    /* Add this if we need to have some form of extended properties for diagrams */
    /*
    IF OBJECT_ID(N'dbo.sysdiagram_properties') IS NULL
    BEGIN
        CREATE TABLE dbo.sysdiagram_properties
        (
            diagram_id int,
            name sysname,
            value varbinary(max) NOT NULL
        )
    END
    */

    IF OBJECT_ID(N'dbo.dtproperties') IS NOT NULL
        begin
            insert into dbo.sysdiagrams
            ([name],
             [principal_id],
             [version],
             [definition])
            select convert(sysname, dgnm.[uvalue]),
                   DATABASE_PRINCIPAL_ID(N'dbo'), -- will change to the sid of sa
                   0,                             -- zero for old format, dgdef.[version],
                   dgdef.[lvalue]
            from dbo.[dtproperties] dgnm
                     inner join dbo.[dtproperties] dggd
                                on dggd.[property] = 'DtgSchemaGUID' and dggd.[objectid] = dgnm.[objectid]
                     inner join dbo.[dtproperties] dgdef
                                on dgdef.[property] = 'DtgSchemaDATA' and dgdef.[objectid] = dgnm.[objectid]

            where dgnm.[property] = 'DtgSchemaNAME'
              and dggd.[uvalue] like N'_EA3E6268-D998-11CE-9454-00AA00A3F36E_'
            return 2;
        end
    return 1;
END
go


