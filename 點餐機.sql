-- 1. 資料表建立 ----------------------------------------------
-- 顧客資料表（PK: CustomerID，對應UserInfo）
IF OBJECT_ID('Customers') IS NOT NULL DROP TABLE Customers;
CREATE TABLE Customers (
    CustomerID NVARCHAR(20) PRIMARY KEY,
    Name NVARCHAR(50),
    CONSTRAINT FK_Customers_UserInfo FOREIGN KEY (CustomerID) REFERENCES UserInfo(uid)
);


-- 訂單主檔（PK: OrderID, FK: CustomerID）
IF OBJECT_ID('Orders') IS NOT NULL DROP TABLE Orders;
CREATE TABLE Orders (
    OrderID INT IDENTITY(1001,1) PRIMARY KEY,
    CustomerID NVARCHAR(20),
    OrderDate DATETIME DEFAULT GETDATE(),
    PlaceType BIT, -- 1:內用, 0:外帶
    Status NVARCHAR(20) DEFAULT 'Pending',
    CONSTRAINT FK_Orders_Customers FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

-- 商品資料表
IF OBJECT_ID('Product') IS NOT NULL DROP TABLE Product;
CREATE TABLE Product (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    ItemName NVARCHAR(100) UNIQUE NOT NULL,
    ProductStatus INT,
    ProductPrice INT NOT NULL,
    StockQuantity INT NOT NULL DEFAULT 0
);

-- 訂單明細（使用 ProductID 外鍵）
IF OBJECT_ID('OrderDetails') IS NOT NULL DROP TABLE OrderDetails;
CREATE TABLE OrderDetails (
    OrderDetailID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID INT,
    ProductID INT,
    Quantity INT,
    ItemPrice INT,
    Customization NVARCHAR(255),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    CONSTRAINT FK_OrderDetails_Product FOREIGN KEY (ProductID) REFERENCES Product(ID)
);

-- 優惠券資料表
IF OBJECT_ID('Coupons') IS NOT NULL DROP TABLE Coupons;
CREATE TABLE Coupons (
    CouponCode NVARCHAR(20) PRIMARY KEY,
    DiscountAmount INT NOT NULL,
    ExpiryDate DATETIME NOT NULL,
    IsUsed BIT DEFAULT 0
);

-- 2. 預存程序 ------------------------------------------------

--1 登入或建立顧客
IF OBJECT_ID('Order_login') IS NOT NULL DROP PROCEDURE Order_login;
GO
CREATE PROCEDURE Order_login
    @CustomerID NVARCHAR(20)
AS
BEGIN
    IF NOT EXISTS (SELECT 1 FROM Customers WHERE CustomerID = @CustomerID)
    BEGIN
        INSERT INTO UserInfo (uid, cname) VALUES (@CustomerID, @CustomerID);
        INSERT INTO Customers (CustomerID, Name) VALUES (@CustomerID, @CustomerID);
    END
    SELECT 1 AS LoginStatus;
END;
GO

--2 建立訂單
IF OBJECT_ID('Order_place') IS NOT NULL DROP PROCEDURE Order_place;
GO
CREATE PROCEDURE Order_place
    @CustomerID NVARCHAR(20),
    @PlaceType BIT,
    @NewOrderID INT OUTPUT
AS
BEGIN
    INSERT INTO Orders (CustomerID, PlaceType)
    VALUES (@CustomerID, @PlaceType);

    SET @NewOrderID = SCOPE_IDENTITY();
END;
GO

--3 使用優惠券
IF OBJECT_ID('Order_coupon') IS NOT NULL DROP PROCEDURE Order_coupon;
GO
CREATE PROCEDURE Order_coupon
    @CustomerID NVARCHAR(20),
    @OrderID INT,
    @CouponCode NVARCHAR(20),
    @ProductID INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
        -- 檢查優惠券是否存在且未過期
    IF EXISTS (
        SELECT 1 FROM Coupons 
        WHERE CouponCode = @CouponCode 
        AND ExpiryDate >= GETDATE()
        AND IsUsed = 0
    )
    BEGIN
        -- 檢查 Order 是否存在（選擇性）
        IF EXISTS (SELECT 1 FROM Orders WHERE OrderID = @OrderID AND CustomerID = @CustomerID)
        BEGIN
            -- 加入優惠項目（假設折抵金額）
            INSERT INTO OrderDetails (OrderID, ProductID, Quantity, ItemPrice)
            VALUES (@OrderID, @ProductID, @Quantity, -50);
            -- 標記優惠券已使用
            UPDATE Coupons SET IsUsed = 1 WHERE CouponCode = @CouponCode;

            SELECT 1 AS Applied;-- 成功
        END
    END
    ELSE
    BEGIN
        SELECT 0 AS Applied;-- 優惠券無效
    END
END;
GO

--4 套餐/單點區分
IF OBJECT_ID('Order_set') IS NOT NULL DROP PROCEDURE Order_set;
GO
CREATE PROCEDURE Order_set
    @CustomerID NVARCHAR(20),
    @OrderID INT,
    @ProductID INT,
    @Quantity INT,
    @IsSet BIT
AS
BEGIN
    DECLARE @Price INT;
    SELECT @Price = CASE 
        WHEN @IsSet = 1 THEN ProductPrice + 65
        ELSE ProductPrice
    END
    FROM Product WHERE ID = @ProductID;

    INSERT INTO OrderDetails (OrderID, ProductID, Quantity, ItemPrice)
    VALUES (@OrderID, @ProductID, @Quantity, @Price);

    SELECT @IsSet AS IsSetResult;
END;
GO

--5 客製化
IF OBJECT_ID('Order_diy') IS NOT NULL DROP PROCEDURE Order_diy;
GO
CREATE PROCEDURE Order_diy
    @CustomerID NVARCHAR(20),
    @OrderID INT,
    @ProductID INT,
    @Quantity INT,
    @Customization NVARCHAR(255)
AS
BEGIN
    DECLARE @Price INT;
    SELECT @Price = ProductPrice FROM Product WHERE ID = @ProductID;

    INSERT INTO OrderDetails (OrderID, ProductID, Quantity, Customization, ItemPrice)
    VALUES (@OrderID, @ProductID, @Quantity, @Customization, @Price);

    SELECT 1 AS Result;
END;
GO

--6 加入購物車
IF OBJECT_ID('Order_meal') IS NOT NULL DROP PROCEDURE Order_meal;
GO
CREATE PROCEDURE Order_meal
    @CustomerID NVARCHAR(20),
    @OrderID INT,
    @ProductID INT,
    @Quantity INT
AS
BEGIN
    DECLARE @ItemPrice INT;
    SELECT @ItemPrice = ProductPrice FROM Product WHERE ID = @ProductID;

    INSERT INTO OrderDetails (OrderID, ProductID, Quantity, ItemPrice)
    VALUES (@OrderID, @ProductID, @Quantity, @ItemPrice);

    SELECT 1 AS CarStatus;
END;
GO

--7 加點（更新）
IF OBJECT_ID('Order_update') IS NOT NULL DROP PROCEDURE Order_update;
GO
CREATE PROCEDURE Order_update
    @CustomerID NVARCHAR(20),
    @OrderID INT,
    @ProductID INT,
    @Quantity INT
AS
BEGIN
    DECLARE @Price INT;
    SELECT @Price = ProductPrice FROM Product WHERE ID = @ProductID;

    INSERT INTO OrderDetails (OrderID, ProductID, Quantity, ItemPrice)
    VALUES (@OrderID, @ProductID, @Quantity, @Price);

    SELECT 1 AS UpdateStatus;
END;
GO

--8 查詢訂單狀態
IF OBJECT_ID('Order_status') IS NOT NULL DROP PROCEDURE Order_status;
GO
CREATE PROCEDURE Order_status
    @CustomerID NVARCHAR(20),
    @OrderID INT
AS
BEGIN
    SELECT 
        CASE 
            WHEN Status = 'Pending' THEN '訂單已送出'
            WHEN Status = 'Completed' THEN '訂單已完成'
            WHEN Status = 'Cancelled' THEN '訂單已取消'
            ELSE '無法識別的狀態或訂單不存在'
        END AS 訂單狀態
    FROM Orders
    WHERE CustomerID = @CustomerID AND OrderID = @OrderID;
END;
GO

-- 3. 測試資料與操作 -----------------------------------------

-- 插入商品
INSERT INTO Product (ItemName, ProductStatus, ProductPrice, StockQuantity)
VALUES 
(N'四盎司牛肉堡', 1, 92, 100),
(N'辣味雙層四盎司牛肉堡', 1, 132, 80),
(N'雙層四盎司分享盒', 1, 450, 50),
(N'辣味四盎司牛肉堡', 1, 92, 60);

--1 顧客登入
EXEC Order_login @CustomerID = 'D25887';

--2 建立訂單（外帶）
DECLARE @OrderID INT;
EXEC Order_place @CustomerID = 'D25887', @PlaceType = 0, @NewOrderID = @OrderID OUTPUT;

--3 插入優惠券
DELETE FROM Coupons WHERE CouponCode = 'MAY50';
INSERT INTO Coupons (CouponCode, DiscountAmount, ExpiryDate)
VALUES ('MAY50', 50, GETDATE() + 1);

--4 使用優惠券（商品 ID 1）
EXEC Order_coupon @CustomerID = 'D25887', @OrderID = @OrderID, @CouponCode = 'MAY50', @ProductID = 1, @Quantity = 1;

--5 套餐（辣味雙層四盎司牛肉堡 ID = 2）
EXEC Order_set @CustomerID = 'D25887', @OrderID = @OrderID, @ProductID = 2, @Quantity = 1, @IsSet = 1;

--6 客製化（去酸黃瓜，商品 ID = 1）
EXEC Order_diy @CustomerID = 'D25887', @OrderID = @OrderID, @ProductID = 1, @Quantity = 1, @Customization = N'去酸黃瓜';

--7 加點（辣味四盎司，ID = 4）
EXEC Order_meal @CustomerID = 'D25887', @OrderID = @OrderID, @ProductID = 4, @Quantity = 1;

--8 再加點（雙層四盎司分享盒，ID = 3）
EXEC Order_update @CustomerID = 'D25887', @OrderID = @OrderID, @ProductID = 3, @Quantity = 1;

--9 查詢狀態
EXEC Order_status @CustomerID = 'D25887', @OrderID = @OrderID;

-- 顯示明細
SELECT OD.*, P.ItemName
FROM OrderDetails OD
JOIN Product P ON OD.ProductID = P.ID
WHERE OD.OrderID = @OrderID;

-- 顯示訂單
SELECT * FROM Orders WHERE OrderID = @OrderID;

-- 顯示優惠券
SELECT * FROM Coupons;


hfdjsaklfjdksal;