package routes

import (
	"proptech-backend/internal/handlers"
	"proptech-backend/internal/middleware"

	"github.com/gin-gonic/gin"
)

func RegisterLeaseRoutes(router *gin.Engine, h *handlers.LeaseHandler) {
	api := router.Group("/api", middleware.AuthRequired())

	api.GET("/leases", h.ListMine)
	api.GET("/agreements/:id/lease", h.GetByAgreement)

	// Direct UPI payments
	api.GET("/owner/upi", h.OwnerUPIGet)
	api.PUT("/owner/upi", h.OwnerUPISet)

	l := api.Group("/leases/:id")
	{
		l.GET("", h.Get)
		l.GET("/events", h.Events)
		l.GET("/rent", h.Rent)
		l.POST("/renewal", h.Renewal)
		l.POST("/renewal/respond", h.RenewalRespond)
		l.POST("/move-out", h.MoveOut)
		l.POST("/move-out/complete", h.MoveOutComplete)
		l.POST("/move-in/confirm", h.MoveInConfirm)

		l.GET("/deposit", h.Deposit)
		l.POST("/deposit/pay", h.DepositPay)
		l.GET("/deposit/upi-link", h.DepositUPILink)
		l.POST("/deposit/upi-submit", h.DepositUPISubmit)
		l.GET("/deposit/proof", h.DepositProof)
		l.GET("/deposit/receipt", h.DepositReceipt)
		l.POST("/deposit/confirm", h.DepositConfirm)
		l.POST("/deposit/reject", h.DepositReject)
		l.POST("/deposit/inspection", h.DepositInspection)
		l.POST("/deposit/deductions", h.DeductionAdd)
		l.DELETE("/deposit/deductions/:deductionId", h.DeductionDelete)
		l.POST("/deposit/settlement", h.DepositSettlement)
		l.POST("/deposit/respond", h.DepositRespond)
		l.POST("/deposit/refund", h.DepositRefund)

		l.POST("/photos", h.PhotoUpload)
		l.GET("/photos", h.PhotoList)
		l.GET("/photos/:photoId", h.PhotoServe)
		l.DELETE("/photos/:photoId", h.PhotoDelete)
		l.GET("/comparison", h.Comparison)
	}

	rent := api.Group("/rent/:paymentId")
	{
		rent.POST("/pay", h.PayRent)
		rent.GET("/upi-link", h.RentUPILink)
		rent.POST("/upi-submit", h.RentUPISubmit)
		rent.GET("/proof", h.RentProof)
		rent.POST("/confirm", h.ConfirmRent)
		rent.POST("/mark-paid", h.MarkRentPaid)
		rent.POST("/reject", h.RejectRent)
		rent.GET("/receipt", h.Receipt)
	}
}