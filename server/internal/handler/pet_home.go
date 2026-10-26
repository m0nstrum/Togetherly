package handler

import (
	"errors"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pethome"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
	"net/http"
)

func PetHome(r *router.Router[*core.RequestEvent], svc *pethome.Service) {
	fail := func(e *core.RequestEvent, err error) error {
		switch {
		case errors.Is(err, pethome.ErrDenied):
			return e.ForbiddenError("Home unavailable", nil)
		case errors.Is(err, pethome.ErrInvalid):
			return e.BadRequestError("Invalid home update", nil)
		case errors.Is(err, pethome.ErrConflict):
			return e.JSON(http.StatusConflict, map[string]any{"error": "home_changed"})
		default:
			return e.InternalServerError("Home unavailable", err)
		}
	}
	send := func(e *core.RequestEvent, rec *core.Record) error {
		if rec == nil {
			return e.JSON(http.StatusOK, map[string]any{"revision": 0, "group_id": e.Request.PathValue("group")})
		}
		// Explicit projection: operation history is never part of the public API.
		return e.JSON(http.StatusOK, map[string]any{"id": rec.Id, "group_id": rec.GetString("group_id"), "revision": rec.GetInt("revision"), "state": rec.GetString("state")})
	}
	r.GET("/api/pet-home/{group}", func(e *core.RequestEvent) error {
		rec, err := svc.Read(e.Request.PathValue("group"), e.Auth.Id)
		if err != nil {
			return fail(e, err)
		}
		return send(e, rec)
	}).Bind(apis.RequireAuth("users"))
	r.POST("/api/pet-home/{group}", func(e *core.RequestEvent) error {
		var body struct {
			Revision  *int   `json:"revision"`
			Operation string `json:"operation"`
			State     string `json:"state"`
		}
		if err := e.BindBody(&body); err != nil || body.Revision == nil {
			return fail(e, pethome.ErrInvalid)
		}
		rec, err := svc.Write(e.Request.PathValue("group"), e.Auth.Id, *body.Revision, body.Operation, body.State)
		if err != nil {
			return fail(e, err)
		}
		return send(e, rec)
	}).Bind(apis.RequireAuth("users"), apis.BodyLimit(140<<10))
}
